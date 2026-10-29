"""Windows companion. Outlook OAuth and Gmail IMAP. Run only on your own PC.
No listener, public endpoint, telemetry, email deletion or read-state mutation.
"""
from __future__ import annotations
import argparse, datetime as dt, email, email.policy, getpass, html, imaplib, json, os
from pathlib import Path
import re, sys, time
from email.utils import parseaddr
from html.parser import HTMLParser
from mail_core import parse_alert, UnsupportedAlert, seal_feed, open_feed, validate_key

APP = 'HearthNative'
class TextHTML(HTMLParser):
    def __init__(self): super().__init__(); self.out=[]; self.skip=0
    def handle_starttag(self, tag, attrs):
        if tag in ('style','script'): self.skip += 1
        if tag in ('br','p','div','tr'): self.out.append('\n')
    def handle_endtag(self, tag):
        if tag in ('style','script'): self.skip=max(0,self.skip-1)
    def handle_data(self, data):
        if not self.skip: self.out.append(data)
def plaintext(value: str) -> str:
    parser=TextHTML(); parser.feed(value); return html.unescape(''.join(parser.out)).replace('\xa0',' ')

def atomic_write(path: Path, data: bytes):
    path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_name(path.name+'.tmp')
    with tmp.open('wb') as f: f.write(data); f.flush(); os.fsync(f.fileno())
    os.replace(tmp,path)

def runtime():
    if sys.platform != 'win32': raise RuntimeError('凭据保存和实际邮箱访问仅支持 Windows；单元测试可在其他平台运行。')
    import keyring
    backend=keyring.get_keyring()
    if 'Windows' not in type(backend).__module__: raise RuntimeError('未检测到 Windows 凭据管理器，拒绝使用明文存储。')
    return keyring

def load_config(path: Path) -> dict:
    c=json.loads(path.read_text(encoding='utf-8-sig'))
    if c.get('provider') not in ('outlook','gmail'): raise ValueError('provider 应为 outlook 或 gmail')
    if not isinstance(c.get('email'),str) or not c['email']: raise ValueError('请填写自己的邮箱地址')
    senders=c.get('allowed_senders')
    if not isinstance(senders,list) or not senders or any(not isinstance(s,str) or '@' not in s or '*' in s for s in senders): raise ValueError('必须填写明确的银行通知发件人地址，不支持通配符。')
    c['allowed_senders']={s.strip().lower() for s in senders}
    c['poll_seconds']=max(120,int(c.get('poll_seconds',300)))
    c['lookback_days']=min(30,max(1,int(c.get('lookback_days',7))))
    output=Path(c.get('output_file','')).expanduser()
    if not output.is_absolute() or output.suffix!='.hearthfeed': raise ValueError('output_file 必须为同步盘中的完整路径，以 .hearthfeed 结尾。')
    c['output_file']=output
    if c['provider']=='outlook' and not re.fullmatch(r'[0-9a-fA-F-]{36}',c.get('client_id','')): raise ValueError('请填写自己注册的 Microsoft 应用 client_id。')
    return c

def outlook_client(c, directory, interactive):
    import msal
    from msal_extensions import PersistedTokenCache, FilePersistenceWithDataProtection
    directory.mkdir(parents=True,exist_ok=True)
    # DPAPI binds cached refresh tokens to this Windows user. Never put this folder in a public repository.
    cache=PersistedTokenCache(FilePersistenceWithDataProtection(str(directory/'msal-cache.bin')))
    app=msal.PublicClientApplication(c['client_id'],authority='https://login.microsoftonline.com/consumers',token_cache=cache)
    scopes=['https://graph.microsoft.com/Mail.Read']
    accounts=app.get_accounts(username=c['email'])
    result=app.acquire_token_silent(scopes,account=accounts[0]) if accounts else None
    if not result or 'access_token' not in result:
        if not interactive: raise RuntimeError('Outlook 授权已失效，请重新运行 --setup。')
        flow=app.initiate_device_flow(scopes=scopes)
        if 'user_code' not in flow: raise RuntimeError('无法发起 Microsoft 授权，请检查 client_id 和公共客户端设置。')
        # A short-lived device code is shown locally only; never sent to logs or GitHub.
        print(flow['message'])
        result=app.acquire_token_by_device_flow(flow)
        if 'access_token' not in result: raise RuntimeError('Outlook 授权未完成。')
    return result['access_token']

def outlook_messages(c, directory):
    import requests
    token=outlook_client(c,directory,False)
    start=(dt.datetime.now(dt.timezone.utc)-dt.timedelta(days=c['lookback_days'])).strftime('%Y-%m-%dT%H:%M:%SZ')
    # Exact sender filters are applied locally as well as server-side; no emails are marked read.
    sender_filter=' or '.join("from/emailAddress/address eq '"+s.replace("'","''")+"'" for s in c['allowed_senders'])
    url='https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages'
    params={'$filter':f'receivedDateTime ge {start} and ({sender_filter})','$select':'id,internetMessageId,from,subject,body','$top':'100'}
    for _ in range(20):
        r=requests.get(url,params=params,headers={'Authorization':'Bearer '+token,'Prefer':'outlook.body-content-type="text"'},timeout=40)
        if r.status_code!=200: raise RuntimeError(f'Outlook 请求失败（HTTP {r.status_code}），未改动邮箱。')
        payload=r.json()
        for m in payload.get('value',[]):
            sender=m.get('from',{}).get('emailAddress',{}).get('address','').lower()
            if sender not in c['allowed_senders']: continue
            body=m.get('body',{})
            body_text=plaintext(body.get('content','')) if body.get('contentType','').lower()=='html' else body.get('content','')
            yield m.get('internetMessageId') or m['id'],m.get('subject','')+'\n'+body_text
        next_url=payload.get('@odata.nextLink')
        if not next_url: return
        if not next_url.startswith('https://graph.microsoft.com/'): raise RuntimeError('Unexpected Graph continuation URL')
        url=next_url;params=None
    raise RuntimeError('银行通知超过本次分页上限，请缩小 lookback_days。本次不写入不完整结果。')

def gmail_messages(c,keyring):
    password=keyring.get_password(APP,c['email']+':gmail')
    if not password: raise RuntimeError('请先运行 --setup 配置 Gmail 应用专用密码。')
    since=(dt.date.today()-dt.timedelta(days=c['lookback_days'])).strftime('%d-%b-%Y')
    with imaplib.IMAP4_SSL('imap.gmail.com',993) as client:
        client.login(c['email'],password);client.select('INBOX',readonly=True)
        uids=set()
        for sender in sorted(c['allowed_senders']):
            if not re.fullmatch(r'[a-zA-Z0-9._+@-]+',sender): raise ValueError('Gmail 发件人地址包含不支持的字符')
            status,data=client.uid('search',None,f'(SINCE "{since}" FROM "{sender}")')
            if status!='OK': raise RuntimeError('Gmail 搜索失败')
            uids.update(data[0].split())
        if len(uids)>2000: raise RuntimeError('匹配通知过多，请缩小 lookback_days。')
        for uid in sorted(uids,key=int):
            # BODY.PEEK avoids marking messages as read. Limit size before fetching the body.
            status,meta=client.uid('fetch',uid,'(RFC822.SIZE)')
            sizes=re.findall(rb'RFC822.SIZE (\d+)',b' '.join(x for x in meta if isinstance(x,bytes)))
            if not sizes or int(sizes[0])>1_000_000: continue
            status,data=client.uid('fetch',uid,'(BODY.PEEK[])')
            if status!='OK': raise RuntimeError('Gmail 读取失败')
            raw=next((v[1] for v in data if isinstance(v,tuple)),None)
            if raw is None: continue
            msg=email.message_from_bytes(raw,policy=email.policy.default)
            if parseaddr(str(msg.get('From','')))[1].lower() not in c['allowed_senders']: continue
            body=msg.get_body(preferencelist=('plain','html'))
            if body is None: continue
            content=body.get_content()
            if not isinstance(content,str): continue
            if body.get_content_type()=='text/html': content=plaintext(content)
            yield str(msg.get('Message-ID') or ('gmail-'+c['email']+'-'+uid.decode())),str(msg.get('Subject',''))+'\n'+content

def run_once(c,keyring,directory):
    key=keyring.get_password(APP,c['email']+':sync')
    if not key: raise RuntimeError('配对密钥未配置，请运行 --setup。')
    output=c['output_file'];statefile=directory/'mail-state.hearthfeed'
    # Keep state encrypted locally too. Never silently reset a corrupted file (would lose history).
    existing=open_feed(statefile.read_bytes(),key) if statefile.exists() else []
    entries={e['sourceID']:e for e in existing};added=skipped=0
    messages=outlook_messages(c,directory) if c['provider']=='outlook' else gmail_messages(c,keyring)
    for message_id,text in messages:
        try: item=parse_alert(text,message_id)
        except UnsupportedAlert: skipped+=1;continue
        if item['sourceID'] not in entries: entries[item['sourceID']]=item;added+=1
    sealed=seal_feed(list(entries.values()),key)
    atomic_write(statefile,sealed)
    atomic_write(output,sealed)
    print(f'{dt.datetime.now():%Y-%m-%d %H:%M} | 新增 {added}，累计 {len(entries)}，跳过不明确通知 {skipped}。')

def main():
    p=argparse.ArgumentParser(description='小家 Windows 信用卡邮件助手')
    p.add_argument('--config',default='config.json');p.add_argument('--setup',action='store_true');p.add_argument('--once',action='store_true')
    args=p.parse_args();keyring=runtime();c=load_config(Path(args.config))
    directory=Path(os.environ['LOCALAPPDATA'])/APP/c['email'].replace('@','_at_').replace('/','_')
    directory.mkdir(parents=True,exist_ok=True)
    if args.setup:
        key=getpass.getpass('在 App「邮件」页生成的配对密钥（输入不显示）：').strip();validate_key(key)
        # Validate existing data before changing the stored key.
        if (directory/'mail-state.hearthfeed').exists():
            old=keyring.get_password(APP,c['email']+':sync')
            if not old: raise RuntimeError('本地已有加密历史但旧密钥丢失，请先恢复旧密钥，避免覆盖。')
            previous=open_feed((directory/'mail-state.hearthfeed').read_bytes(),old)
            atomic_write(directory/'mail-state.hearthfeed',seal_feed(previous,key))
        keyring.set_password(APP,c['email']+':sync',key)
        if c['provider']=='gmail':
            password=getpass.getpass('Gmail 应用专用密码（不是账号密码）：').replace(' ','')
            if not password: raise ValueError('密码不能为空')
            keyring.set_password(APP,c['email']+':gmail',password)
        else: outlook_client(c,directory,True)
        print('配对已保存在 Windows 凭据管理器；不会写入配置文件。')
        run_once(c,keyring,directory);return
    while True:
        try: run_once(c,keyring,directory)
        except Exception as error:
            # Provider exceptions may embed request details. Only output type, not raw token/body/error payload.
            print('本次同步失败（'+type(error).__name__+'）。原有账目保留。请检查网络、配置和授权；必要时重跑 --setup。')
            if args.once: return 1
        if args.once: return 0
        time.sleep(c['poll_seconds'])
if __name__=='__main__':
    try: sys.exit(main())
    except KeyboardInterrupt: print('\n已停止。')
    except Exception as error: print('启动失败：'+str(error) if isinstance(error,(ValueError,RuntimeError)) else '启动失败，请检查安装及配置。');sys.exit(1)
