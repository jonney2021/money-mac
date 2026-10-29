"""Strict CAD purchase parser and encrypted interchange. Never logs email bodies."""
from __future__ import annotations
import base64, datetime as dt, hashlib, json, re, secrets
from decimal import Decimal
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

FORMAT = 'hearth-feed-v1'
MAX_CENTS = 9_999_999_999

class UnsupportedAlert(ValueError): pass

def parse_alert(text: str, message_id: str | None = None) -> dict:
    if len(text) > 100_000: raise UnsupportedAlert('message too large')
    text = re.sub(r'\s+', ' ', text.replace('\xa0', ' '))
    if re.search(r'\b(?:USD|EUR|GBP|CNY|HKD)\b|US\$|美元|人民币|欧元', text, re.I): raise UnsupportedAlert('not CAD')
    if re.search(r'\b(?:refund|refunded|payment received|payment due|statement|declined|reversed|pending)\b|退款|还款|账单|拒绝|撤销|待处理', text, re.I): raise UnsupportedAlert('not a final purchase')
    if not re.search(r'\b(?:purchase|purchased|transaction|was used|spent)\b|消费|交易', text, re.I): raise UnsupportedAlert('not a purchase notification')
    amounts = re.findall(r'(?:CAD\s*\$?|C\$|\$)\s*((?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2})(?!\d)|((?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2})\s*CAD\b', text, re.I)
    if len(amounts) != 1: raise UnsupportedAlert('ambiguous amount')
    if not re.search(r'\bCAD\b|C\$', text, re.I): raise UnsupportedAlert('currency not explicit')
    cents = int(Decimal((amounts[0][0] or amounts[0][1]).replace(',', '')) * 100)
    if not 0 < cents <= MAX_CENTS: raise UnsupportedAlert('invalid amount')
    merchant = re.search(r'\bat\s+([^\r\n]+?)\s+(?:for|on)\b|(?:商户|商家)[：:]\s*([^\r\n，,。]+)', text, re.I)
    if not merchant: raise UnsupportedAlert('merchant missing')
    name = (merchant.group(1) or merchant.group(2)).strip()
    if not 0 < len(name) <= 200: raise UnsupportedAlert('invalid merchant')
    dates = set(re.findall(r'\b20\d{2}-\d{2}-\d{2}\b', text))
    if len(dates) != 1: raise UnsupportedAlert('transaction date missing or ambiguous')
    day = dates.pop()
    try: dt.date.fromisoformat(day)
    except ValueError as error: raise UnsupportedAlert('invalid date') from error
    source = message_id or ' '.join(text.split()).lower()
    digest = hashlib.sha256(source.encode('utf-8')).hexdigest()
    return dict(id='mail-' + digest, kind='expense', cents=cents, merchant=name, date=day,
                category=suggest_category(name), member='共同', account='信用卡', note='', sourceID='mail:' + digest, needsReview=True)

def suggest_category(name: str) -> str:
    n = name.lower()
    for names, category in [(['costco','walmart','metro','iga','provigo','super c'],'超市日用'),(['coffee','tim hortons','restaurant','starbucks'],'餐饮美食'),(['hydro','bell','videotron'],'居家账单'),(['stm','uber','esso','shell'],'交通出行')]:
        if any(s in n for s in names): return category
    return '其他'

def validate_key(key_hex: str) -> bytes:
    if not re.fullmatch(r'[a-fA-F0-9]{64}', key_hex.strip()): raise ValueError('配对密钥必须为 64 位十六进制字符。')
    return bytes.fromhex(key_hex.strip())

def seal_feed(entries: list[dict], key_hex: str) -> bytes:
    if len(entries) > 10_000: raise ValueError('同步记录超过 10000，请归档后重新开始。')
    plain = json.dumps({'version':1,'entries':entries}, ensure_ascii=False, separators=(',',':')).encode('utf-8')
    nonce = secrets.token_bytes(12)
    combined = nonce + AESGCM(validate_key(key_hex)).encrypt(nonce, plain, FORMAT.encode())
    envelope = json.dumps({'format': FORMAT, 'sealed':base64.b64encode(combined).decode()},separators=(',',':')).encode()
    if len(envelope) > 12_000_000: raise ValueError('同步文件超过大小上限。')
    return envelope

def open_feed(data: bytes, key_hex: str) -> list[dict]:
    envelope = json.loads(data)
    if envelope.get('format') != FORMAT: raise ValueError('invalid format')
    combined = base64.b64decode(envelope['sealed'], validate=True)
    plain = AESGCM(validate_key(key_hex)).decrypt(combined[:12], combined[12:], FORMAT.encode())
    payload = json.loads(plain)
    if payload['version'] != 1: raise ValueError('invalid version')
    return payload['entries']
