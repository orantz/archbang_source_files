#!/bin/bash
# Configure live iso
set -e -u -x

# Set locales
sed -i 's/#\(en_US\.UTF-8\)/\1/' /etc/locale.gen
locale-gen

# Add ArchBang repo
sed -i "\$a[archbang]\nServer = http://www.archbang.org/repo" /etc/pacman.conf

# Set timezone
ln -sf /usr/share/zoneinfo/America/Montreal /etc/localtime

# Fix parcellite icon
ln -sf /usr/share/icons/AwOken/clear/24x24/actions/editpaste.png /usr/share/pixmaps/parcellite.png

# Fix Firefox ugly fonts...
ln -s /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/

# Add live user
useradd -m -p "" -g users -G "adm,storage,optical,audio,video,network,wheel,power,lp,log" -s /bin/bash live
chown live /home/live

# Remove gtk-docs
rm -rf /usr/share/{doc,gtk-doc,info,gtk-2.0,gtk-3.0}

# Clean /etc/skel
rm -rf /etc/skel

#Clean '#' from mirrlist
#sed -i "s/#Server/Server/g" /etc/pacman.d/mirrorlist

sed 's#\(^ExecStart=-/sbin/agetty\)#\1 --autologin live#;
     s#\(^Alias=getty.target.wants/\).\+#\1autologin@tty1.service#' \
     /usr/lib/systemd/system/getty@.service > /etc/systemd/system/autologin@.service

systemctl disable getty@tty1.service
systemctl enable multi-user.target pacman-init.service autologin@.service lastmin.service NetworkManager.service
