sudo useradd -m -s /bin/bash devops
sudo passwd devops
echo 'devops ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/devops
sudo chmod 0440 /etc/sudoers.d/devops
sudo visudo -cf /etc/sudoers.d/devops


sudo sshd -T | grep -i passwordauthentication

sudo grep -ri PasswordAuthentication /etc/ssh/sshd_config /etc/ssh/sshd_config.d/

echo 'PasswordAuthentication yes' | sudo tee /etc/ssh/sshd_config.d/01-passwordauth.conf

sudo sshd -t
sudo systemctl reload sshd

sudo sshd -T | grep -i passwordauthentication
# passwordauthentication yes
