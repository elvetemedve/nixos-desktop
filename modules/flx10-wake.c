/* flx10-wake.c - clear the DDJ-FLX10 jog screens' "NO AUDIO DRIVER" message.
 *
 * The firmware shows that message ~3 s after USB attach unless the host proves
 * it speaks the AlphaTheta vendor protocol.  One read is enough:
 *
 *     bmRequestType 0xC0 (IN | vendor | device)
 *     bRequest      0x00
 *     wValue        0x0000
 *     wIndex        0xC001      (firmware version register)
 *     wLength       2
 *
 * This is READ-ONLY.  Nothing is ever written to the device.  Verified on
 * firmware 1.14: the message appears, this clears it.
 *
 * Deliberately depends on nothing but libc - it is driven from udev on every
 * plug-in, so it must not break when the Nix store is garbage collected.
 *
 * Build:  nix-shell -p gcc --run 'gcc -O2 -Wall -o flx10-wake flx10-wake.c'
 * Run:    flx10-wake [-v] [/dev/bus/usb/BBB/DDD]
 *         Honours udev's $BUSNUM / $DEVNUM when no path is given.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <dirent.h>
#include <sys/ioctl.h>
#include <linux/usbdevice_fs.h>

#define VID 0x2b73
#define PID 0x0041
#define USB_DIR "/dev/bus/usb"
#define RETRIES 3

static int verbose;

__attribute__((format(printf,1,2)))
static void vlog(const char *fmt, ...)
{
    if (!verbose) return;
    va_list ap; va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap);
}

/* Read the 18-byte device descriptor that usbfs prepends to the node. */
static int is_flx10(const char *path)
{
    unsigned char d[18];
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0;
    ssize_t n = read(fd, d, sizeof d);
    close(fd);
    if (n != (ssize_t)sizeof d || d[1] != 0x01) return 0;
    unsigned vid = d[8] | (d[9] << 8);
    unsigned pid = d[10] | (d[11] << 8);
    return vid == VID && pid == PID;
}

static int find_flx10(char *out, size_t outsz)
{
    DIR *b = opendir(USB_DIR);
    if (!b) return -1;
    struct dirent *bd;
    while ((bd = readdir(b))) {
        if (bd->d_name[0] == '.') continue;
        char busdir[300];
        snprintf(busdir, sizeof busdir, USB_DIR "/%s", bd->d_name);
        DIR *v = opendir(busdir);
        if (!v) continue;
        struct dirent *vd;
        while ((vd = readdir(v))) {
            if (vd->d_name[0] == '.') continue;
            char path[600];
            snprintf(path, sizeof path, "%s/%s", busdir, vd->d_name);
            if (is_flx10(path)) {
                snprintf(out, outsz, "%s", path);
                closedir(v); closedir(b);
                return 0;
            }
        }
        closedir(v);
    }
    closedir(b);
    return -1;
}

static int wake(const char *path)
{
    unsigned char buf[2] = { 0, 0 };
    struct usbdevfs_ctrltransfer ct = {
        .bRequestType = 0xC0,
        .bRequest     = 0x00,
        .wValue       = 0x0000,
        .wIndex       = 0xC001,
        .wLength      = sizeof buf,
        .timeout      = 500,
        .data         = buf,
    };
    int fd = open(path, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        vlog("flx10-wake: open %s: %s\n", path, strerror(errno));
        return -1;
    }
    int r = ioctl(fd, USBDEVFS_CONTROL, &ct);
    close(fd);
    if (r < 0) {
        vlog("flx10-wake: control transfer: %s\n", strerror(errno));
        return -1;
    }
    vlog("flx10-wake: %s -> firmware %u.%02u\n", path, buf[0], buf[1]);
    return 0;
}

int main(int argc, char **argv)
{
    char path[PATH_MAX] = "";

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-v")) verbose = 1;
        else snprintf(path, sizeof path, "%s", argv[i]);
    }

    if (!path[0]) {
        /* udev exports these for usb_device events. */
        const char *bus = getenv("BUSNUM"), *dev = getenv("DEVNUM");
        if (bus && dev) snprintf(path, sizeof path, USB_DIR "/%s/%s", bus, dev);
    }
    if (!path[0] && find_flx10(path, sizeof path) < 0) {
        vlog("flx10-wake: no DDJ-FLX10 found\n");
        return 1;
    }

    for (int i = 0; i < RETRIES; i++) {
        if (wake(path) == 0) return 0;
        usleep(50 * 1000);
    }
    return 1;
}
