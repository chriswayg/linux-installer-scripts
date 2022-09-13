#!/bin/bash
set -e

## Bash Script to Install KDE Plasma from Backports Extra on Ubuntu Server 22.04 LTS
## used on a standard install of ubuntu-22.04.1-live-server-amd64.iso
# This script is largely idempotent, which means it can be run more than once, in case of an error for example.

## Usage (additional logs in /var/log/, increase 'run=02' to prevent caching after making changes):
#  use 'script' command for logging (logging via '| tee ' did not work as it hangs & prevents responses to user input)
#
#    script -q -a install-kde-plasma.log
#    bash <(curl -Ls https://raw.githubusercontent.com/chriswayg/linux-installer-scripts/main/install-plasma.sh?run=01)
#    exit   # or Ctrl-D or to close the script log
#    sudo reboot

# Work-around for a bug where whiptail/dialog is becoming unresponsive & the cursor is missing in terminal
# using sudo -E (--preserve-env) to make sure that 'needrestart' will not prompt repeatedly
sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure debconf --frontend=readline --priority=critical
export DEBIAN_FRONTEND=readline
export NEEDRESTART_SUSPEND=true
sudo -E apt-get update

# Change this to the relevant timezone
sudo timedatectl set-timezone Asia/Manila

echo "***** Preventing Firefox Snap version from being installed *****"
[ ! -f /etc/apt/preferences.d/firefox-snap-prevent ] && echo 'Package: firefox*
Pin: release o=Ubuntu 
Pin-Priority: -1
' | sudo tee /etc/apt/preferences.d/firefox-snap-prevent > /dev/null

[ ! -f /var/log/installed-packages-server.log ] && sudo dpkg --get-selections | sudo tee /var/log/installed-packages-server.log > /dev/null

echo "***** Installing Backports Repositories with latest versions of KDE Plasma *****"
[ ! -f /etc/apt/sources.list.d/kubuntu-ppa-ubuntu-backports-jammy.list ] && sudo add-apt-repository ppa:kubuntu-ppa/backports -y
[ ! -f /etc/apt/sources.list.d/kubuntu-ppa-ubuntu-backports-extra-jammy.list ] && sudo add-apt-repository ppa:kubuntu-ppa/backports-extra -y

echo "***** Installing & configuring apt-fast to speed up Plasma download *****"
[ ! -f /etc/apt/sources.list.d/apt-fast-ubuntu-stable-jammy.list ] && sudo add-apt-repository ppa:apt-fast/stable -y
cat > ~/debconf-aptfast << "EOF"
apt-fast	apt-fast/aptmanager	select	apt-get
apt-fast	apt-fast/maxdownloads	string	10
apt-fast	apt-fast/dlflag	boolean	true
EOF

sudo debconf-set-selections debconf-aptfast
rm ~/debconf-aptfast

sudo -E apt-get install -yq apt-fast

# Using this sequence of installation, Firefox Snap is expected to NOT be installed

echo "***** Installing Kubuntu Desktop *****"
sudo -E apt-fast install -yq kubuntu-desktop

echo "***** Installing some additional Kubuntu Desktop packages (via tasksel) *****"
sudo -E apt-get install -yq tasksel
sudo -E apt-fast install -yq kubuntu-desktop^

echo "***** Installing Kubuntu restricted extras & addons incl MS fonts *****"
sudo -E apt-fast install -yq kubuntu-restricted-extras kubuntu-restricted-addons

echo "***** Adding Wayland as an option *****"
# note: copy-paste from & to macOS <-> Parallels VM does not work in Wayland
sudo -E apt-get install -yq kwin-wayland plasma-workspace-wayland
sudo -E apt-get install -yq $(check-language-support -l en)

echo "***** Removing Maui SSDM theme to ensure that Breeze will be the default *****"
# usually this has not been installed anyways
sudo -E apt-get purge -yq sddm-theme-debian-maui

echo "***** Removing cloud-init *****"
# cloud-init is not useful on the desktop
sudo -E apt-get purge -yq cloud-init
sudo rm -rfv /etc/cloud && sudo rm -rfv /var/lib/cloud/

# ensuring that netplan.io will not be autoremoved
sudo -E apt-mark manual netplan.io

echo "***** Configuring the Network via Netplan & NetworkManager *****"
echo '# Let NetworkManager manage all devices on this system
network:
  version: 2
  renderer: NetworkManager
' | sudo tee /etc/netplan/00-installer-config.yaml > /dev/null

sudo netplan generate
sudo netplan apply

echo "***** Enabling Graphical Boot *****"
# replacing the complete line only if no other options have been set
sudo sed -i.bak '/^GRUB_CMDLINE_LINUX_DEFAULT=""/c\GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' /etc/default/grub
sudo -E update-grub

echo "***** Replacing Kubuntu Boot Splash with Breeze as default  *****"
# TODO: this still requires manually setting Breeze as boot splash in Settings -> Appearance -> Boot Splash Screen
# change back-and-forth with 'Apply' (possibly restart) between Breeze (Text Mode) and Breeze for the setting to be applied
#sudo -E apt-get purge -yq plymouth-theme-kubuntu-logo plymouth-theme-spinner plymouth-theme-ubuntu-text plymouth-theme-kubuntu-text
sudo -E apt-get install -yq kde-config-plymouth plymouth-theme-breeze

# this does not really activate breeze
#sudo mkdir -p /etc/plymouth/
#echo '[Daemon] 
#Theme=breeze
#' | sudo tee /etc/plymouth/plymouthd.conf > /dev/null

# this does not show breeze.plymouth as an available option
#sudo -E update-alternatives --config default.plymouth
#sudo -E update-initramfs -u

echo "***** Configuring KDE Plasma Settings (Splash, Numlock, Automatic Updates) *****"
kwriteconfig5 --file ksplashrc --group KSplash --key Theme "org.kde.breeze.desktop"
kwriteconfig5 --file kcminputrc --group Keyboard --key NumLock 0
kwriteconfig5 --file PlasmaDiscoverUpdates --group Global --key UseUnattendedUpdates --type bool true
kwriteconfig5 --file discoverrc --group Software --key UseOfflineUpdates --type bool true
kwriteconfig5 --file dolphinrc --group DetailsMode --key PreviewSize 22
# minimize notification popups from other applications (for example appimaged)
kwriteconfig5 --file plasmanotifyrc --group Applications --group @other --key ShowInHistory --type bool true
kwriteconfig5 --file plasmanotifyrc --group Applications --group @other --key ShowPopups --type bool false

echo "***** Installing Firefox from PPA & setting it as Default *****"
# remove snap version, just in case
sudo snap remove firefox
[ ! -f /etc/apt/sources.list.d/mozillateam-ubuntu-ppa-jammy.list ] && sudo add-apt-repository ppa:mozillateam/ppa -y

[ ! -f /etc/apt/preferences.d/firefox-mozillateam ] && echo 'Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
' | sudo tee /etc/apt/preferences.d/firefox-mozillateam > /dev/null

[ ! -f /etc/apt/apt.conf.d/51unattended-upgrades-firefox ] && echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:jammy";' | sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox
sudo -E apt-get install --allow-downgrades -y firefox

# set Firefox as default in Plasma
kwriteconfig5 --file kdeglobals --group "General" --key BrowserApplication "firefox.desktop" 
kwriteconfig5 --file mimeapps.list --group "Added Associations" --key "x-scheme-handler/http" "firefox.desktop;"
kwriteconfig5 --file mimeapps.list --group "Added Associations" --key "x-scheme-handler/https" "firefox.desktop;"
kwriteconfig5 --file mimeapps.list --group "Default Applications" --key "x-scheme-handler/http" "firefox.desktop;"
kwriteconfig5 --file mimeapps.list --group "Default Applications" --key "x-scheme-handler/https" "firefox.desktop;"

echo "***** Adding a desktop launcher to run Dolphin as Root *****"
mkdir -p ~/.local/share/applications/
cat > ~/.local/share/applications/dolphin-root.desktop << "EOF"
[Desktop Entry]
Name=Dolphin (as Root)
Exec=pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY KDE_SESSION_VERSION=5 KDE_FULL_SESSION=true dolphin /
Icon=system-file-manager
Type=Application
Categories=Qt;KDE;System;FileTools;FileManager;
GenericName=File Manager
Terminal=false
MimeType=inode/directory;
Keywords=files;file management;file browsing;samba;network shares;Explorer;Finder;
EOF

echo "***** Installing prerequisites for Parallels Tools *****"
sudo -E apt-get install -yq gcc make dkms libelf-dev

echo "***** Installing Flatpak and Appimage support *****"
sudo -E apt-get install -yq flatpak plasma-discover-backend-flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

sudo flatpak install -y appimagepool
mkdir -p ~/Applications
[[ ! -n $(shopt -s nullglob; echo ~/Applications/appimaged-*.AppImage) ]] && wget -c https://github.com/$(wget -q https://github.com/probonopd/go-appimage/releases -O - | grep "appimaged-.*-x86_64.AppImage" | head -n 1 | cut -d '"' -f 2) -P ~/Applications/ && chmod +x ~/Applications/appimaged-*.AppImage && ~/Applications/appimaged-*.AppImage
# TODO: the last command results in a timeout with: "ERROR: notification: Process org.freedesktop.Notifications exited with status 1", but still works

echo "***** Installing deb-get for 3rd party deb packages *****"
curl -sL https://raw.githubusercontent.com/wimpysworld/deb-get/main/deb-get | sudo -E bash -s install deb-get

echo "***** Updating the current installation, cleanup *****"
sudo -E apt-get update
sudo -E apt-get upgrade -yq

# Restore debconf defaults
sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure debconf --frontend=dialog --priority=high

# Cleanup 
sudo -E apt-get -yq autoremove
sudo -E apt-get -yq clean
sudo -E apt-fast -yq clean
sudo -E deb-get clean

[ ! -f /var/log/installed-packages-desktop.log ] && sudo dpkg --get-selections | sudo tee /var/log/installed-packages-desktop.log > /dev/null

echo ""
echo "***** Exit the log & Reboot now! *****"
