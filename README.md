# AVRecorderPlus

[![Build Status](https://travis-ci.org/smokris/AVRecorderPlus.svg?branch=master)](https://travis-ci.org/smokris/AVRecorderPlus)

Apple's AVRecorder sample app, modified to add a few features:

   - added a recording duration indicator
   - added separate left/right VU meters
   - added VU history charts
   - modified to automatically save to a file on the desktop, instead of providing a File Save dialog (which risks deleting the recording if you accidentally press Cancel)
   - added support for iOS device recording
   - modified to write movie fragment atoms every 10 seconds, so you don't lose the entire recording when the app or system inevitably crashes
   - modified to automatically resume recording if it unexpectedly stops for some reason (e.g., if the "maximum allowable length" has been reached)
