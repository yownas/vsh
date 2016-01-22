# Goals

vsh, the client part, should work seamlessly on Linux, FreeBSD, OSX and Solaris. Please, no optimizations that break compability.

vshd is a script that figures out which operating system it is installed on and then run the real script in libexec.

All scripts should be able to work on a clean minimal install. Maybe not always possible, but we could atleast try.

# TODOS

* Support for Solaris Zones and FreeBSD Jails
* Better documentation with example and use-cases

# DONES

* Add support for physical "clients" and proxied containers.
* Move functions and other things that can/should be reused from libexec/vshd-Linux to vshd / js

# DQA - Developer Questions and Answers

Add questions/answers below. :)

    Q: Do I add questions here?
    A: Yes.
