/// No-op on VM and mobile. Web registers a pagehide flush separately.
void listenForPageUnload(void Function() flush) {}
