
import '@expo/metro-runtime';
import { registerRootComponent } from 'expo';
import App from './App';
import TrackPlayer from 'react-native-track-player-cjx';
import PlaybackService from './service';

// registerRootComponent calls AppRegistry.registerComponent('main', () => App);
// It also ensures that whether you load the app in Expo Go or in a native build,
// the environment is set up appropriately
registerRootComponent(App);
// 防止热重载或多次注册导致重复注册TrackPlayer Service
if (!(global as any).__TRACK_PLAYER_SERVICE_REGISTERED__) {
  TrackPlayer.registerPlaybackService(() => PlaybackService);
  (global as any).__TRACK_PLAYER_SERVICE_REGISTERED__ = true;
}
