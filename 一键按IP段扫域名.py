apt-get update -y && apt-get install -y zmap python3-pip


# 1. 安装专业的 TLS/证书解析底层库
pip3 install cryptography cryptography >/dev/null 2>&1 || apt-get install -y python3-cryptography

# 2. 写入终极 DER 证书解包脚本
cat << 'EOF' > get_domains_der.py
import socket
import ssl
import sys
import subprocess
import concurrent.futures
from cryptography import x509
from cryptography.hazmat.backends import default_backend

TARGET_CIDRS = "3.112.0.0/16 13.113.0.0/16 13.114.0.0/16 13.158.0.0/16 13.231.0.0/16 18.182.0.0/16 18.183.0.0/16 35.77.0.0/16 35.78.0.0/16"

print("⚡ [1/2] 正在利用 ZMap 扫描 AWS 同机房 443 端口...")
cmd = f"zmap -p 443 {TARGET_CIDRS} -n 50000 -B 20M -q"
try:
    output = subprocess.check_output(cmd, shell=True, text=True)
    ip_list = [ip.strip() for ip in output.splitlines() if ip.strip()]
    print(f"🎯 成功定位到 {len(ip_list)} 个响应 443 端口的活跃 IP！")
except Exception as e:
    print(f"❌ ZMap 运行失败: {e}")
    sys.exit(1)

print("🔍 [2/2] 启动底层 DER 二进制证书解包引擎...")

valid_domains = set()
MAX_DOMAINS = 5000
open("us_reality_domains.txt", "w").close()

def parse_ip(ip):
    if len(valid_domains) >= MAX_DOMAINS:
        return
    
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    try:
        with socket.create_connection((ip, 443), timeout=1.2) as sock:
            # 不发送 SNI 伪装，只获取原始服务端证书
            with ctx.wrap_socket(sock) as ssock:
                der_cert = ssock.getpeercert(binary_form=True)
                if not der_cert:
                    return
                
                # 利用 cryptography 库底层强行解析 DER 证书
                cert = x509.load_der_x509_certificate(der_cert, default_backend())
                domains = []
                
                # 尝试提取 SAN 扩展
                try:
                    san_ext = cert.extensions.get_extension_for_oid(x509.OID_SUBJECT_ALTERNATIVE_NAME)
                    for name in san_ext.value.get_values_for_type(x509.DNSName):
                        domains.append(name)
                except Exception:
                    pass
                
                # 尝试提取 Subject CN
                try:
                    for attribute in cert.subject.get_attributes_for_oid(x509.OID_COMMON_NAME):
                        domains.append(attribute.value)
                except Exception:
                    pass

                for domain in domains:
                    d = domain.lstrip('*.').lower()
                    if (
                        '.' in d and
                        not d.endswith('.amazonaws.com') and
                        not d.endswith('.cloudfront.net') and
                        not d.endswith('.internal') and
                        not d.endswith('.local') and
                        not d.startswith('ec2-') and
                        not d.startswith('ip-')
                    ):
                        if d not in valid_domains:
                            valid_domains.add(d)
                            sys.stdout.write(f"\r[进度: {len(valid_domains)}/{MAX_DOMAINS}] 发现新域名: {d}\n")
                            sys.stdout.flush()
                            with open("us_reality_domains.txt", "a") as f:
                                f.write(d + "\n")
                            if len(valid_domains) >= MAX_DOMAINS:
                                break
    except Exception:
        pass

with concurrent.futures.ThreadPoolExecutor(max_workers=150) as executor:
    executor.map(parse_ip, ip_list)

print(f"\n✅ 完成！已成功抓取并保存 {len(valid_domains)} 个符合 REALITY 标准的纯净美国域名至 us_reality_domains.txt！")
EOF

python3 get_domains_der.py