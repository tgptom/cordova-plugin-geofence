interface TransitionType {
  ENTER: number;
  EXIT: number;
  BOTH: number;
  DWELL: number;
}

interface Window {
  geofence: GeofencePlugin;
  TransitionType: TransitionType;
}

interface GeofencePlugin {
  initialize(
    successCallback?: (result: any) => void,
    errorCallback?: (error: string) => void
  ): Promise<InitializeResult>;

  addOrUpdate(
    geofence: Geofence | Geofence[],
    successCallback?: (result: any) => void,
    errorCallback?: (error: string) => void
  ): Promise<any>;

  replace(
    geofence: Geofence | Geofence[],
    successCallback?: (result: any) => void,
    errorCallback?: (error: string | { code: string; message: string }) => void
  ): Promise<any>;

  remove(
    id: string | number | Array<string | number>,
    successCallback?: (result: any) => void,
    errorCallback?: (error: string) => void
  ): Promise<any>;

  removeAll(
    successCallback?: (result: any) => void,
    errorCallback?: (error: string) => void
  ): Promise<any>;

  getWatched(
    successCallback?: (result: any) => void,
    errorCallback?: (error: string) => void
  ): Promise<string>;

  dismissNotifications(ids: string | number | Array<string | number>): void;

  snooze(id: string | number, duration: number): void;

  ping(
    successCallback?: (result: any) => void,
    errorCallback?: (error: string) => void
  ): Promise<any>;

  onTransitionReceived: (geofences: Geofence[]) => void;

  receiveTransition?: (geofences: Geofence[]) => void;
  
  onNotificationClicked: (notificationData: Object) => void;

  onMonitoringError: (error: Object) => void;
}

interface Geofence {
  id: string;
  latitude: number;
  longitude: number;
  radius: number;
  transitionType: number;
  /**
   * Android only: set true to allow http:// transition callback URLs for development.
   * HTTPS is required by default.
   */
  allowInsecureHttp?: boolean;
  startTime?: Date;
  endTime?: Date;
  notification?: Notification;
}

interface InitializeResult {
  locationPermissionGranted: boolean;
  backgroundLocationPermissionGranted: boolean;
  notificationPermissionRequired: boolean;
  notificationPermissionGranted: boolean;
  preciseLocationRequired: boolean;
  preciseLocationGranted: boolean;
  warnings: string[];
}

interface Notification {
  id?: number;
  title?: string;
  text: string;
  smallIcon?: string;
  icon?: string;
  openAppOnClick?: boolean;
  vibration?: number[];
  data?: Object;
}
