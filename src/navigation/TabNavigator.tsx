import React, { useState, memo } from 'react';
import { View, TouchableOpacity, StyleSheet } from 'react-native';
import Icon from 'react-native-vector-icons/MaterialIcons';
import HomeScreen from '../screens/HomeScreen';
import SearchScreen from '../screens/SearchScreen';
import SettingsScreen from '../screens/SettingsScreen';
import MiniPlayer from '../components/MiniPlayer';
import { usePlayer } from '../contexts/PlayerContext';

const TAB_ITEMS = [
  { name: 'Search', icon: 'search' },
  { name: 'Home', icon: 'music-note' },
  { name: 'Settings', icon: 'settings' },
] as const;

const TabButton = memo(({
  icon,
  isActive,
  onPress
}: {
  icon: string;
  isActive: boolean;
  onPress: () => void;
}) => (
  <TouchableOpacity
    style={[styles.tab, isActive && styles.tabActive]}
    onPress={onPress}
  >
    <Icon
      name={icon}
      size={28}
      color={isActive ? '#2196F3' : '#fff'}
    />
  </TouchableOpacity>
));
TabButton.displayName = 'TabButton';

// 必须定义在模块级：定义在组件内部会在每次渲染时创建新组件类型，
// 导致 MiniPlayer 子树被卸载重挂载（内部 state 丢失、封面重新加载）
const MiniPlayerWrapper = memo(() => {
  const { currentSong } = usePlayer();
  if (!currentSong) return null;
  return <MiniPlayer />;
});
MiniPlayerWrapper.displayName = 'MiniPlayerWrapper';

const TabNavigator = () => {
  const [activeTab, setActiveTab] = useState<string>('Home');

  const handleTabPress = (tabName: string) => {
    setActiveTab(tabName);
  };

  const renderScreen = () => {
    switch (activeTab) {
      case 'Search':
        return <SearchScreen />;
      case 'Settings':
        return <SettingsScreen />;
      default:
        return <HomeScreen />;
    }
  };

  return (
    // 注意：PlayerProvider 已由 App.tsx 提供，此处不再重复嵌套，
    // 否则会导致 TrackPlayer 双重初始化、播放状态分裂与双倍定时器
    <View style={styles.container}>
      <View style={styles.tabBar}>
        {TAB_ITEMS.map(({ name, icon }) => (
          <TabButton
            key={name}
            icon={icon}
            isActive={activeTab === name}
            onPress={() => handleTabPress(name)}
          />
        ))}
      </View>
      <View style={styles.content}>{renderScreen()}</View>
      <MiniPlayerWrapper />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0a1428',
  },
  tabBar: {
    flexDirection: 'row',
    backgroundColor: 'rgba(0,27,46,0.98)',
    height: 64,
    borderTopLeftRadius: 18,
    borderTopRightRadius: 18,
    boxShadow: '0 -2px 8px rgba(0,0,0,0.1)', // web 兼容阴影
    marginHorizontal: 12,
    marginBottom: 8,
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 24,
  },
  tab: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    marginHorizontal: 8,
    height: 48,
    borderRadius: 16,
    backgroundColor: 'transparent',
  },
  tabActive: {
    backgroundColor: '#13304a',
    borderRadius: 16,
  },
  content: {
    flex: 1,
    backgroundColor: '#0a1428',
  },
});

export default memo(TabNavigator);
