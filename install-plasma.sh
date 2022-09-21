#!/bin/bash
set -e

## Bash Script to Install KDE Plasma from Backports Extra on Ubuntu Server or Kubuntu Desktop 22.04 LTS 
## use on a standard install of ubuntu-22.04.1-live-server-amd64.iso (with SSH) or kubuntu-22.04.1-desktop-amd64.iso
#
# The result is very similar, but the install using Kubuntu.iso takes considerably longer.
# The Server.iso based install has /boot separate and some additional server packages (ssh, htop, needrestart, ...) remaining.
# While the Kubuntu.iso based install is missing some KDE games, but has efibootmgr, partitionmanager, secure boot utilities 
# and grub-efi added and also has the default Documents, Pictures, etc. folders configured for desktop users. 
# see: Diff SERVER - KUBUNTU based.txt
# 
# This script is largely idempotent, which means it can be run more than once, in case of an error for example.

## USAGE (additional logs in /var/log/, increase 'run=02' to prevent caching after making changes):
#  use 'script' command for logging (logging via '| tee ' did not work as it hangs & prevents responses to user input)
#  run this as a normal user (the script will ask for sudo elevation)
#
#    sudo apt install curl # only when using kubuntu.iso
#    script -q -a install-kde-plasma.log
#    bash <(curl -Ls https://raw.githubusercontent.com/chriswayg/linux-installer-scripts/main/install-plasma.sh?run=01)
#
#    # enter sudo password & wait a few minutes
#    # only the MS Fonts installer will require confirmation
#    # note: the appimaged installer will timeout after a minute waiting for the notification service
#
#    exit   # or Ctrl-D or to close the script log
#    sudo reboot

## TODO: - determine if installation was originally made from Server.iso or Kubuntu.iso
#        - Using: `read -r firstline</var/log/installer/media-info` (search for "Ubuntu-Server")
#        - use conditionals to only execute the commands required for the installation mode and try to keep
#          the code required for the Server.iso mostly together in one section

# Disabling whiptail/dialog during installation (due to bugginess) and preventing configuration dialogs as much as possible
# using sudo -E (--preserve-env) to make sure that 'needrestart' will not prompt repeatedly
sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure debconf --frontend=readline --priority=critical
export DEBIAN_FRONTEND=readline
export NEEDRESTART_SUSPEND=true  # (only needed for Server.iso)
sudo -E apt-get update

# only run this once to record the installed default packages before changes are made
[ ! -f /var/log/installed-packages-default.log ] && sudo dpkg --get-selections | sudo tee /var/log/installed-packages-default.log > /dev/null

# change this to the relevant timezone (only needed for Server.iso, as Kubuntu installer sets this up properly)
sudo timedatectl set-timezone Asia/Manila

echo -e "\n***** Installing Backports Repositories with latest versions of KDE Plasma *****"
[ ! -f /etc/apt/sources.list.d/kubuntu-ppa-ubuntu-backports-jammy.list ] && sudo add-apt-repository --no-update ppa:kubuntu-ppa/backports -y
[ ! -f /etc/apt/sources.list.d/kubuntu-ppa-ubuntu-backports-extra-jammy.list ] && sudo add-apt-repository --no-update ppa:kubuntu-ppa/backports-extra -y

echo -e "\n***** Installing & configuring apt-fast to speed up Plasma download *****"
[ ! -f /etc/apt/sources.list.d/apt-fast-ubuntu-stable-jammy.list ] && sudo add-apt-repository --no-update ppa:apt-fast/stable -y
cat > ~/debconf-aptfast << "EOF"
apt-fast	apt-fast/aptmanager	select	apt-get
apt-fast	apt-fast/maxdownloads	string	10
apt-fast	apt-fast/dlflag	boolean	true
EOF

sudo debconf-set-selections debconf-aptfast
rm ~/debconf-aptfast

sudo -E apt-get update
sudo -E apt-get install -yq apt-fast

echo -e "\n***** Upgrading the current installation *****"
# if Kubuntu was already installed (Kubuntu.iso based), this will upgrade KDE Plasma using backports-extra
sudo -E apt-fast upgrade -yq

# Using this sequence of installation, Firefox Snap is expected to NOT be installed (on Server.iso)

echo -e "\n***** Installing Kubuntu Desktop *****" # (only needed for Server.iso)
sudo -E apt-fast install -yq kubuntu-desktop

echo -e "\n***** Installing additional Kubuntu Desktop (via tasksel) & KDE Plasma packages *****"
sudo -E apt-get install -yq tasksel
sudo -E apt-fast install -yq kubuntu-desktop^
sudo -E apt-fast install -yq kde-plasma-desktop
# optionally install an additional 145+ packages for KDE standard or 550+ packages for the full KDE desktop
#sudo -E apt-fast install -yq kde-standard
#sudo -E apt-fast install -yq kde-full

echo -e "\n***** Installing Kubuntu restricted extras & addons incl MS fonts *****"
sudo -E apt-fast install -yq kubuntu-restricted-extras kubuntu-restricted-addons

echo -e "\n***** Adding Wayland as an option *****"
# note: copy-paste from & to macOS <-> Parallels VM does not work in Wayland
sudo -E apt-fast install -yq kwin-wayland plasma-workspace-wayland
# prevent errors regarding missing language support
sudo -E apt-fast install -yq $(check-language-support -l en)

echo -e "\n***** Removing Maui SSDM theme to ensure that Breeze will be the default *****"
# usually this has not been installed anyways (this should not be needed)
sudo -E apt-get purge -yq sddm-theme-debian-maui

echo -e "\n***** Removing cloud-init *****"
# cloud-init is not useful on the desktop (only needed for Server.iso)
sudo -E apt-get purge -yq cloud-init cloud-guest-utils cloud-initramfs-copymods	cloud-initramfs-dyn-netconf
sudo rm -rfv /etc/cloud && sudo rm -rfv /var/lib/cloud/

# ensuring that netplan.io will not be autoremoved (this should not be needed)
sudo -E apt-mark manual netplan.io

echo -e "\n***** Configuring the Network via Netplan & NetworkManager *****"
# this will overwrite any previous configuration (only needed for Server.iso)
echo '# Let NetworkManager manage all devices on this system
network:
  version: 2
  renderer: NetworkManager
' | sudo tee /etc/netplan/00-installer-config.yaml > /dev/null

sudo netplan generate
sudo netplan apply

echo -e "\n***** Enabling Graphical Boot *****"
# replacing the complete line only if no other options have been set (only needed for Server.iso)
sudo sed -i.bak '/^GRUB_CMDLINE_LINUX_DEFAULT=""/c\GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' /etc/default/grub
sudo -E update-grub

echo -e "\n***** Installing Breeze Kubuntu Boot Splash *****"
# TODO: this still requires manually setting Breeze as boot splash in Settings -> Appearance -> Boot Splash Screen
# change back-and-forth with 'Apply' (possibly restart) between Breeze (Text Mode) and Breeze for the setting to be applied
# (attempted to replace Kubuntu Boot Splash with Breeze as default using the commented out lines)
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

echo -e "\n***** Configuring KDE Plasma Settings (Splash, Numlock, Automatic Updates) *****"
kwriteconfig5 --file ksplashrc --group KSplash --key Theme "org.kde.breeze.desktop"
kwriteconfig5 --file kcminputrc --group Keyboard --key NumLock 0
kwriteconfig5 --file PlasmaDiscoverUpdates --group Global --key UseUnattendedUpdates --type bool true
kwriteconfig5 --file discoverrc --group Software --key UseOfflineUpdates --type bool true
kwriteconfig5 --file dolphinrc --group DetailsMode --key PreviewSize 22
# minimize notification popups from other applications (for example appimaged)
kwriteconfig5 --file plasmanotifyrc --group Applications --group @other --key ShowInHistory --type bool true
kwriteconfig5 --file plasmanotifyrc --group Applications --group @other --key ShowPopups --type bool false
# Creating a full suite of localized default user directories within the $HOME directory (only needed for Server.iso)
xdg-user-dirs-update --force

echo -e "\n***** Installing Firefox from PPA & setting it as Default *****"
## reasons for not using Firefox Snap: slow start, incompatible with KeePassXC
# remove snap version (only needed for Kubuntu.iso)
sudo snap remove firefox gnome-3-38-2004 gtk-common-themes
rm -rf ~/snap/firefox
[ ! -f /etc/apt/sources.list.d/mozillateam-ubuntu-ppa-jammy.list ] && sudo add-apt-repository ppa:mozillateam/ppa -y

# remove tarball installed Firefox (only checking the default locations, not needed on a fresh install)
# https://support.mozilla.org/en-US/kb/install-firefox-linux#w_install-firefox-from-mozilla-builds-for-advanced-users
[ -f /usr/local/bin/firefox ] && sudo rm -v /usr/local/bin/firefox /usr/local/share/applications/firefox.desktop
[ -d /opt/firefox ] && sudo rm -rf /opt/firefox

# preventing Firefox Snap version from being installed
[ ! -f /etc/apt/preferences.d/firefox-snap-prevent ] && echo 'Package: firefox*
Pin: release o=Ubuntu 
Pin-Priority: -1
' | sudo tee /etc/apt/preferences.d/firefox-snap-prevent > /dev/null

[ ! -f /etc/apt/preferences.d/firefox-mozillateam ] && echo 'Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
' | sudo tee /etc/apt/preferences.d/firefox-mozillateam > /dev/null

[ ! -f /etc/apt/apt.conf.d/51unattended-upgrades-firefox ] && echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:jammy";' | sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox
sudo -E apt-get install --allow-downgrades -yq firefox

# set Firefox as default in Plasma
kwriteconfig5 --file kdeglobals --group "General" --key BrowserApplication "firefox.desktop" 
kwriteconfig5 --file mimeapps.list --group "Added Associations" --key "x-scheme-handler/http" "firefox.desktop;"
kwriteconfig5 --file mimeapps.list --group "Added Associations" --key "x-scheme-handler/https" "firefox.desktop;"
kwriteconfig5 --file mimeapps.list --group "Default Applications" --key "x-scheme-handler/http" "firefox.desktop;"
kwriteconfig5 --file mimeapps.list --group "Default Applications" --key "x-scheme-handler/https" "firefox.desktop;"

echo -e "\n***** Adding a desktop launcher to run Dolphin as Root *****"
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

echo -e "\n***** Installing prerequisites for Parallels Tools *****"
sudo -E apt-get install -yq gcc make dkms libelf-dev

echo -e "\n***** Installing Flatpak and Appimage support *****"
sudo -E apt-get install -yq flatpak plasma-discover-backend-flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

sudo flatpak install -y appimagepool
mkdir -p ~/Applications
[[ ! -n $(shopt -s nullglob; echo ~/Applications/appimaged-*.AppImage) ]] && wget -c https://github.com/$(wget -q https://github.com/probonopd/go-appimage/releases -O - | grep "appimaged-.*-x86_64.AppImage" | head -n 1 | cut -d '"' -f 2) -P ~/Applications/ && chmod +x ~/Applications/appimaged-*.AppImage && ~/Applications/appimaged-*.AppImage
# TODO: the last command results in a timeout with: "ERROR: notification: Process org.freedesktop.Notifications exited with status 1", but still works

echo -e "\n***** Installing deb-get for 3rd party deb packages *****"
# TODO: add installing developer related packages (including manually added to deb-get)
[ ! -f /usr/bin/deb-get ] && curl -sL https://raw.githubusercontent.com/wimpysworld/deb-get/main/deb-get | sudo -E bash -s install deb-get
sudo deb-get install brave-browser
sudo deb-get install keepassxc
sudo deb-get install nextcloud-desktop
sudo -E apt-get install -yq dolphin-nextcloud

echo -e "\n***** Updating the current installation, cleanup *****"
sudo -E apt-get update
sudo -E apt-fast upgrade -yq

# add some packages
sudo -E apt-get install -yq efibootmgr partitionmanager # (when using Server.iso)
sudo -E apt-get install -yq htop ktorrent # (when using Kubuntu.iso)

# Cleanup 
sudo -E apt-get -yq autoremove
sudo -E apt-get -yq clean
sudo -E apt-fast -yq clean
sudo -E deb-get clean

# Restore debconf defaults
sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure debconf --frontend=dialog --priority=high

# only run this once to get the installed packages after the KDE Plasma desktop has been installed
[ ! -f /var/log/installed-packages-desktop.log ] && sudo dpkg --get-selections | sudo tee /var/log/installed-packages-desktop.log > /dev/null

echo -e "\n***** Exit the log & Reboot now! *****"
