const assert = require('assert');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const iosFilePath = path.join(repoRoot, 'src/ios/GeofencePlugin.swift');
const androidFilePath = path.join(repoRoot, 'src/android/GeofenceTrackingContract.java');
const readmePath = path.join(repoRoot, 'README.md');

const expectedContract = 'AppGeofenceTrackingTransition';
const oldContract = String.fromCharCode(80, 65, 80, 65) + 'GeofenceTrackingTransition';

const iosSource = fs.readFileSync(iosFilePath, 'utf8');
const androidSource = fs.readFileSync(androidFilePath, 'utf8');
const readmeSource = fs.readFileSync(readmePath, 'utf8');

assert(
  iosSource.includes(`let ${expectedContract} = "${expectedContract}"`),
  'iOS contract symbol/string must be exactly AppGeofenceTrackingTransition'
);
assert(
  iosSource.includes(`Notification.Name(rawValue: ${expectedContract})`),
  'iOS transition posting must use AppGeofenceTrackingTransition'
);
assert(
  androidSource.includes(`IOS_TRANSITION_NOTIFICATION = "${expectedContract}"`),
  'Android iOS-transition contract string must be exactly AppGeofenceTrackingTransition'
);
assert(
  readmeSource.includes(`\`${expectedContract}\``),
  'README must document AppGeofenceTrackingTransition'
);

assert(!iosSource.includes(oldContract), 'iOS source must not contain old contract string');
assert(!androidSource.includes(oldContract), 'Android source must not contain old contract string');
assert(!readmeSource.includes(oldContract), 'README must not contain old contract string');
