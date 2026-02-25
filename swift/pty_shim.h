// pty_shim.h — Bridging header exposing forkpty/ioctl to Swift
// Required because these POSIX/BSD functions aren't available in Swift directly.

#ifndef PTY_SHIM_H
#define PTY_SHIM_H

#include <util.h>       // forkpty
#include <sys/ioctl.h>  // ioctl, TIOCSWINSZ, struct winsize
#include <termios.h>    // struct termios

#endif
