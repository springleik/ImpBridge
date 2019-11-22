# ImpBridge
AC Impedance Bridge server for iOS, client runs on MacOS.

As described at http://www.williamsonic.com/ImpBridge/index.html

Screen shot of iOS app which measures AC impedance.  External bridge circuit is driven by the headphone ouput, imbalance is detected through the mic input.  Runs as a measurement server, exposing a socket interface over WiFi.

![iOS Screen Capture](iOS-ImpBridge.png "iOS ImpBridge")

Screen shot of MacOS client app interacting with measurement server through a socket interface.

![MacOS Screen Capture](MacOS-ImpBridge.png "MacOS ImpBridge")

Detector circuit measures bridge imbalance, adapted for connection to the mic input of a handheld device.

![Bridge Detector Circuit](Schematic.png "Detector Schematic")
