import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { BottomTabNavigationProp } from '@react-navigation/bottom-tabs';
import { SongResponse } from './api';

export type RootStackParamList = {
  Home: undefined;
  ServerSelect: undefined;
  Login: {
    serverId: string;
    serverName: string;
  };
  Main: undefined;
  Player: undefined;
  HomeMain: undefined;
  Queue: undefined;
  DailyRecommendDetail: { songs: SongResponse[] };
};

export type TabParamList = {
  Home: undefined;
  Search: undefined;
  Settings: undefined;
};

export type NavigationProp = NativeStackNavigationProp<RootStackParamList>;
export type TabNavigationProp = BottomTabNavigationProp<TabParamList>; 