#!/bin/bash
# update and upgrade os
sudo apt-get update
#sudo apt-get upgrade -y
#sudo apt-get autoremove -y
#
## add my ssh key on root user
#sudo curl -fsSL https://github.com/amirreza1998/devops-scenarios/blob/main/id_rsa.pub -o /root/.ssh/authorized_keys
#
## copy bashrc
#sudo cp /home/vagrant/.bashrc /root/
#
## install docker
#which docker || { curl -fsSL https://get.docker.com | bash; }
#sudo usermod -aG docker $USER
#sudo usermod -aG docker vagrant
