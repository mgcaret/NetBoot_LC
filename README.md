# NetBoot LC

NetBoot LC is an alternative Apple II Workstation boot program for the Apple //e Card for Macintosh LC.

The built-in Apple II Workstation functionality of the card closely mimics the combination of an Enhanced //e with a Workstation Card in all aspects except two:

  - It shares the AppleTalk node address with the host Macintosh. This is not really a problem, because most client applications don't care what the node number is (unless you want to access File Sharing or an AppleShare server on the host Macintosh - see here).
  - It does not load the boot blocks over the network, instead they are contained within the IIe Startup application's BBLK resources. This might be a problem depending on your use cases or preferences. For reference, the Apple II boot blocks contain ProDOS and the Logon program.

The main problems I see with the “firm-coded” boot blocks are:

They are more difficult to update as they require use of ResEdit each time a new ProDOS is released. While this was not a problem for some 25 years, new ProDOS releases have changed that.
The behavior is not the same as the combination of Enhanced //e and Workstation Card.
It is not clear to me why Apple decided to do it differently in the //e Card. My guesses are: It adds a little bit of speed; it prevents some administrative issues where the boot blocks served over the network have not been updated to meet a requirement of the card; and perhaps the engineers of the Card knew that the next version of AppleShare Server was going to drop Apple II boot support.

In any case, after a small and successful quest to update the boot blocks to ProDOS 2.4.1 and Logon 1.5, I decided that I wanted the //e Card to boot like my other //es with Workstation Cards, and NetBoot LC is the result.

## What it Does

NetBoot LC replaces the firm-coded ProDOS 1.9 and Logon 1.3 boot blocks in the IIe Startup program with a new program that downloads boot blocks over the network like any Enhanced //e with a Workstation Card.

Along the way, it also provides some useful info such as the the workstation node address, bridge node number, AppleTalk zone, and boot server address and name. There is a nice spinner that lets you know something is happening.

If the boot is happening due to system cold start and fails before the boot block download starts, the next slot will be tried (if “scan” is configured in the slot preferences).

A status letter is indicated on the lower-left corner of the screen, useful for figuring out what is slow or failing:

  * ``F``: Finding Workstation Card.
  * ``R``: Relocating $300 code.
  * ``I``: Initializing Workstation Card & Getting Info.
  * ``Z``: Identifying local Zone.
  * ``L``: Looking for boot server.
  * ``B``: Downloading boot blocks. At this point spinner will start after the first block is retrieved.

## Building

The only supported build environment for the moment is MacOS X.

Requirements:

  * Working cc65 installation with binaries in PATH.
  * Apple command-line developer tools (``xcode-select --install``).
  * Make sure you have the following binaries in your PATH:
     * ``hexdump``
     * ``Rez``
     * ``macbinary``
     
There is a make target to build a disk image and execute in Virtual ][.  To use it you will need AppleCommander and will need to edit the Makefile.  This is for testing and is otherwise not necessary to build the code and use it.

The build process uses resource forks, your filesystem must support them.

To build, change to the project directory and execute ``make``.

## Installation

  - Download NetBoot LC to your Macintosh.
  - Decode the Macbinary file. The resulting file will look like an application, but it is not and clicking it will do nothing.
  - Open NetBoot LC and a copy of IIe Startup in ResEdit.
  - Open the BBLK resources in the copy of IIe Startup, there should be one resource with ID 5120.
  - Delete BBLK ID 5120.
  - Open the BBLK resources in NetBoot LC.
  - Copy ID 5120 from NetBoot LC to the BBLK resources in the copy of IIe Startup.
  - Quit ResEdit, save the copy of IIe Startup on your way out.

At this point launching IIe Startup and booting over AppleTalk should work as described above.

Obviously, to be useful, you need an AppleShare 2.x/3.x server or netatalk server, with Apple II booting set up, to make use of this.

## Technical / Developing

I recommend having a look at the source code.  It's a bit of a mess but it demonstrates some undocumented Apple II AppleTalk functionality, as well as use of ATP.

If you add features or fix bugs, please send a pull request.


