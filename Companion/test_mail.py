import base64, json, tempfile, unittest
from pathlib import Path
from cryptography.exceptions import InvalidTag
from mail_core import parse_alert, UnsupportedAlert, seal_feed, open_feed, validate_key
from monitor import plaintext, atomic_write, load_config

ALERT='Your card ending 1234 was used at COSTCO for CAD 86.42 on 2026-10-24.'
KEY='01'*32
class MailTests(unittest.TestCase):
    def test_exact_cents_and_category(self):
        e=parse_alert(ALERT);self.assertEqual(e['cents'],8642);self.assertEqual(e['merchant'],'COSTCO');self.assertEqual(e['category'],'超市日用');self.assertTrue(e['needsReview'])
    def test_decimal_not_float(self):
        self.assertEqual(parse_alert(ALERT.replace('86.42','0.29'))['cents'],29)
    def test_comma_amount(self):
        self.assertEqual(parse_alert(ALERT.replace('86.42','1,086.42'))['cents'],108642)
    def test_currency_suffix(self):
        self.assertEqual(parse_alert(ALERT.replace('CAD 86.42','86.42 CAD'))['cents'],8642)
    def test_ambiguous_or_unsupported(self):
        for text in [ALERT+' Balance CAD 200.00',ALERT.replace('CAD','USD'),ALERT.replace('CAD ',''),ALERT+' pending',ALERT+' refund',ALERT+' statement',ALERT.replace('2026-10-24','2026-02-30'),ALERT.replace('on 2026-10-24',''),ALERT.replace('86.42','0.00'),ALERT.replace('at COSTCO for','for')]:
            with self.subTest(text=text),self.assertRaises(UnsupportedAlert):parse_alert(text)
    def test_message_id_dedup_stable(self):
        self.assertEqual(parse_alert(ALERT,'<id@example>')['sourceID'],parse_alert(ALERT+' \n','<id@example>')['sourceID'])
        self.assertNotEqual(parse_alert(ALERT,'<id2@example>')['sourceID'],parse_alert(ALERT,'<id@example>')['sourceID'])
    def test_normalized_dedup(self):
        self.assertEqual(parse_alert(ALERT)['sourceID'],parse_alert(ALERT.replace(' ', '\n'))['sourceID'])
    def test_authenticated_roundtrip(self):
        items=[parse_alert(ALERT)];a=seal_feed(items,KEY);b=seal_feed(items,KEY)
        self.assertNotEqual(a,b);self.assertEqual(open_feed(a,KEY),items);self.assertNotIn(b'COSTCO',a)
        with self.assertRaises(InvalidTag):open_feed(a,'02'*32)
        envelope=json.loads(a);data=bytearray(base64.b64decode(envelope['sealed']));data[-1]^=1;envelope['sealed']=base64.b64encode(data).decode()
        with self.assertRaises(InvalidTag):open_feed(json.dumps(envelope).encode(),KEY)
    def test_bad_key(self):
        for key in ['abc','x'*64,'01'*31]:
            with self.subTest(key=key),self.assertRaises(ValueError):validate_key(key)
    def test_html(self):
        self.assertEqual(plaintext('<script>bad()</script><p>CAD&nbsp;12.34</p>').strip(),'CAD 12.34')
    def test_atomic_file(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'nested'/'feed.hearthfeed';atomic_write(p,b'first');atomic_write(p,b'second');self.assertEqual(p.read_bytes(),b'second');self.assertFalse(p.with_name(p.name+'.tmp').exists())
    def test_sender_allowlist_required(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'config.json';p.write_text(json.dumps({'provider':'outlook','email':'me@example.com','allowed_senders':[]}))
            with self.assertRaises(ValueError):load_config(p)
if __name__=='__main__':unittest.main()
