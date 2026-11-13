# ==========================================
# KAMING OS - Master Makefile
# ==========================================

SHELL := /bin/bash
VERSION := 1.0.0
BUILD_DIR := build
ROOTFS_DIR := $(BUILD_DIR)/rootfs
ISO_DIR := $(BUILD_DIR)/iso
OUTPUT_ISO := $(BUILD_DIR)/kaming-os-$(VERSION)-x86_64.iso

.PHONY: all clean prepare rootfs iso test

all: clean prepare rootfs iso

clean:
	@echo "==> Cleaning build artifacts..."
	sudo rm -rf $(BUILD_DIR)

prepare:
	@echo "==> Creating directory structure..."
	mkdir -p $(ROOTFS_DIR) $(ISO_DIR)/boot/grub $(ISO_DIR)/live

rootfs: prepare
	@echo "==> Bootstrapping base system (Ubuntu Jammy)..."
	sudo debootstrap --arch=amd64 jammy $(ROOTFS_DIR) http://archive.ubuntu.com/ubuntu/
	
	@echo "==> Installing system dependencies and desktop packages inside rootfs..."
	sudo chroot $(ROOTFS_DIR) /bin/bash -c "export DEBIAN_FRONTEND=noninteractive && \
		apt-get update && \
		apt-get install -y linux-image-generic systemd-sysv wayland-compositor \
		pipewire network-manager qt6-base-dev qml6-module-qtquick wine64 dxvk sudo locales"
	
	@echo "==> Injecting Kaming OS local files and translations..."
	sudo mkdir -p $(ROOTFS_DIR)/usr/share/kaming
	sudo cp -r i18n $(ROOTFS_DIR)/usr/share/kaming/ 2>/dev/null || true

iso: rootfs
	@echo "==> Compressing rootfs into SquashFS..."
	sudo mksquashfs $(ROOTFS_DIR) $(ISO_DIR)/live/filesystem.squashfs -b 1048576 -comp xz
	
	@echo "==> Copying kernel and initrd..."
	sudo cp $(ROOTFS_DIR)/boot/vmlinuz-* $(ISO_DIR)/boot/vmlinuz
	sudo cp $(ROOTFS_DIR)/boot/initrd.img-* $(ISO_DIR)/boot/initrd
	
	@echo "==> Configuring GRUB bootloader..."
	echo 'set timeout=5' > $(ISO_DIR)/boot/grub/grub.cfg
	echo 'set default=0' >> $(ISO_DIR)/boot/grub/grub.cfg
	echo 'menuentry "Kaming OS (Live / Install)" {' >> $(ISO_DIR)/boot/grub/grub.cfg
	echo '    linux /boot/vmlinuz boot=live quiet splash' >> $(ISO_DIR)/boot/grub/grub.cfg
	echo '    initrd /boot/initrd' >> $(ISO_DIR)/boot/grub/grub.cfg
	echo '}' >> $(ISO_DIR)/boot/grub/grub.cfg
	
	@echo "==> Generating bootable ISO image..."
	grub-mkrescue -o $(OUTPUT_ISO) $(ISO_DIR) -- -volid "KAMING_OS_$(VERSION)"
	@echo "==> SUCCESS! ISO created at: $(OUTPUT_ISO)"

test:
	@echo "==> Running automated boot test in QEMU..."
	qemu-system-x86_64 -enable-kvm -m 2048 -smp 2 -cdrom $(OUTPUT_ISO) -boot d -nographic -monitor unix:qemu-monitor-socket,server,nowait & \
	PID=$$!; \
	sleep 25; \
	echo "screendump $(BUILD_DIR)/boot_screenshot.ppm" | nc -U qemu-monitor-socket || true; \
	kill $$PID || true
	@echo "==> Test finished. Screenshot saved to $(BUILD_DIR)/boot_screenshot.ppm"
