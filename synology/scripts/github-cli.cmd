# Installs Github CLI (x86_64) for all users on DSM
sudo sh -c 'GH_VERSION=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep tag_name | cut -d \" -f 4 | sed "s/^v//"); wget https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz -O /tmp/gh.tar.gz; cd /tmp; tar -xzf gh.tar.gz; cp gh_${GH_VERSION}_linux_amd64/bin/gh /opt/bin/; chmod 755 /opt/bin/gh'
gh --version
