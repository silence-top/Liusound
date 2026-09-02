import React, { useState, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  TextInput,
  SafeAreaView,
  Modal,
  ImageBackground,
  Animated,
  StatusBar,
  NativeSyntheticEvent,
  NativeScrollEvent,
} from 'react-native';
import Icon from 'react-native-vector-icons/MaterialIcons';
import { SongResponse } from '../types/api';
import { usePlayer } from '../contexts/PlayerContext';
import MiniPlayer from './MiniPlayer';

const HEADER_MAX_HEIGHT = 260;
const HEADER_MIN_HEIGHT = 64 + (StatusBar.currentHeight || 0);
const COVER_SIZE = 90;
const STICKY_BAR_HEIGHT = HEADER_MIN_HEIGHT;
const PLAY_ALL_BAR_HEIGHT = 48;

interface PlaylistDetailProps {
  visible: boolean;
  onClose: () => void;
  songs: SongResponse[];
  title: string;
  coverUrl?: string;
  date?: string;
  showDate?: boolean;
  showActions?: boolean;
  onPlaySong?: (song: SongResponse) => void;
  onPlayAll?: (songs: SongResponse[]) => void;
}

const PlaylistDetail: React.FC<PlaylistDetailProps> = ({
  visible,
  onClose,
  songs,
  title,
  coverUrl,
  date,
  showDate = true,
  showActions = true,
  onPlaySong,
  onPlayAll,
}) => {
  const { setCurrentSong, addToQueue, clearQueue } = usePlayer();
  const [search, setSearch] = useState('');
  const scrollY = useRef(new Animated.Value(0)).current;
  const [showFixedPlayAll, setShowFixedPlayAll] = React.useState(false);
  const flatListRef = useRef<FlatList>(null);

  // 搜索过滤
  const filteredSongs = songs.filter(song =>
    song.title.includes(search) || song.artist?.includes(search) || song.album?.includes(search)
  );

  // 全部播放
  const handlePlayAll = () => {
    if (songs && songs.length > 0) {
      clearQueue();
      addToQueue(songs);
      setCurrentSong(songs[0]);
    }
  };

  // 只渲染全部播放Bar（吸顶）
  const renderPlayAllBar = () => (
    <View style={styles.playAllBar}>
      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
        <TouchableOpacity style={styles.playAllBtn} onPress={() => onPlayAll ? onPlayAll(songs) : handlePlayAll()}>
          <Icon name="play-circle-filled" size={28} color="#fff" />
        </TouchableOpacity>
        <Text style={styles.playAllText}>全部播放</Text>
        <Text style={styles.playAllCount}>（共{filteredSongs.length}首）</Text>
      </View>
      {showActions && (
        <View style={styles.playAllActions}>
          <TouchableOpacity style={styles.playAllActionBtn}>
            <Icon name="radio-button-checked" size={22} color="#b2d7f7" />
          </TouchableOpacity>
          <TouchableOpacity style={styles.playAllActionBtn}>
            <Icon name="queue-music" size={22} color="#b2d7f7" />
          </TouchableOpacity>
          <TouchableOpacity style={styles.playAllActionBtn}>
            <Icon name="play-arrow" size={22} color="#b2d7f7" />
          </TouchableOpacity>
        </View>
      )}
    </View>
  );

  // 搜索框item
  const renderSearchBarItem = () => (
    <View style={styles.searchBar}>
      <Icon name="search" size={20} color="#888" style={{ marginLeft: 8 }} />
      <TextInput
        style={styles.searchInput}
        placeholder="搜索歌曲/专辑/歌手"
        placeholderTextColor="#aaa"
        value={search}
        onChangeText={setSearch}
      />
      <TouchableOpacity>
        <Icon name="filter-list" size={22} color="#888" style={{ marginRight: 8 }} />
      </TouchableOpacity>
    </View>
  );

  // 数据源：只包含歌曲
  const dataWithHeader = filteredSongs;

  // 歌曲列表项
  const renderItem = ({ item, index }: { item: any; index: number }) => {
    // 计算码率（Kbps）
    let bitrateStr = '';
    if (item.size && item.duration) {
      const kbps = Math.round((item.size * 8) / item.duration / 1000);
      bitrateStr = `flac ${kbps}K`;
    }
    return (
      <TouchableOpacity onPress={() => onPlaySong ? onPlaySong(item) : setCurrentSong(item)}>
        <View style={styles.songRow}>
          <Text style={styles.songIndex}>{index + 1}</Text>
          <View style={styles.songInfoWrap}>
            <Text style={styles.songTitle} numberOfLines={1}>{item.title}</Text>
            <View style={styles.songSubInfoRow}>
              <View style={styles.songFormatBox}>
                <Text style={styles.songFormat}>{bitrateStr}</Text>
              </View>
              <Text style={styles.songSub} numberOfLines={1}>{item.artist} - {item.album}</Text>
            </View>
          </View>
          <TouchableOpacity style={styles.songMoreBtn}>
            <Icon name="more-vert" size={22} color="#fff" />
          </TouchableOpacity>
        </View>
      </TouchableOpacity>
    );
  };

  // 头部动画
  const headerHeight = scrollY.interpolate({
    inputRange: [0, HEADER_MAX_HEIGHT - HEADER_MIN_HEIGHT],
    outputRange: [HEADER_MAX_HEIGHT, HEADER_MIN_HEIGHT],
    extrapolate: 'clamp',
  });
  const coverScale = scrollY.interpolate({
    inputRange: [0, HEADER_MAX_HEIGHT - HEADER_MIN_HEIGHT],
    outputRange: [1, 0.6],
    extrapolate: 'clamp',
  });
  const coverTranslateY = scrollY.interpolate({
    inputRange: [0, HEADER_MAX_HEIGHT - HEADER_MIN_HEIGHT],
    outputRange: [0, -20],
    extrapolate: 'clamp',
  });
  const titleOpacity = scrollY.interpolate({
    inputRange: [0, HEADER_MAX_HEIGHT - HEADER_MIN_HEIGHT - 20],
    outputRange: [1, 0],
    extrapolate: 'clamp',
  });
  const stickyBarOpacity = scrollY.interpolate({
    inputRange: [HEADER_MAX_HEIGHT - HEADER_MIN_HEIGHT - 10, HEADER_MAX_HEIGHT - HEADER_MIN_HEIGHT + 30],
    outputRange: [0, 1],
    extrapolate: 'clamp',
  });

  // 动态吸顶：滚动到封面消失后才吸顶
  React.useEffect(() => {
    const listener = scrollY.addListener(({ value }) => {
      if (value >= HEADER_MAX_HEIGHT - HEADER_MIN_HEIGHT) {
        setShowFixedPlayAll(true);
      } else {
        setShowFixedPlayAll(false);
      }
    });
    return () => scrollY.removeListener(listener);
  }, [scrollY]);

  // ListHeaderComponent渲染全部播放+搜索框，吸顶时只渲染搜索框
  const renderListHeader = () => (
    <View>
      {!showFixedPlayAll && (
        <>
          {renderPlayAllBar()}
          <View style={styles.playAllDivider} />
        </>
      )}
      {renderSearchBarItem()}
    </View>
  );

  const handleScrollEnd = (e: NativeSyntheticEvent<NativeScrollEvent>) => {
    const y = e.nativeEvent.contentOffset.y;
    const threshold = HEADER_MAX_HEIGHT - HEADER_MIN_HEIGHT;
    if (y > 0 && y < threshold) {
      if (y < threshold / 2) {
        // 回弹到顶部
        flatListRef.current?.scrollToOffset({ offset: 0, animated: true });
      } else {
        // 吸顶
        flatListRef.current?.scrollToOffset({ offset: threshold, animated: true });
      }
    }
  };

  return (
    <Modal
      visible={visible}
      animationType="fade"
      transparent={true}
      onRequestClose={onClose}
    >
      <View style={styles.modalBg}>
        {/* 吸顶栏 */}
        <Animated.View style={[styles.stickyBar, { opacity: stickyBarOpacity, backgroundColor: stickyBarOpacity.interpolate({inputRange: [0, 1], outputRange: ['rgba(10,20,40,0)', 'rgba(10,20,40,0.98)']}), position: 'absolute', top: 0, left: 0, right: 0, zIndex: 20 }]}> 
          <SafeAreaView style={styles.stickyBarContent}>
            <TouchableOpacity style={styles.stickyBackBtn} onPress={onClose}>
              <Icon name="arrow-back" size={24} color="#fff" />
            </TouchableOpacity>
            <View style={styles.stickyBarTitleWrap}>
              <Text style={styles.stickyBarTitle}>{title}</Text>
              {showDate && date && <Text style={styles.stickyBarDate}>{date}</Text>}
            </View>
            <TouchableOpacity style={styles.stickyMenuBtn}>
              <Icon name="more-vert" size={24} color="#fff" />
            </TouchableOpacity>
          </SafeAreaView>
        </Animated.View>
        {/* 动态吸顶的全部播放Bar */}
        {showFixedPlayAll && (
          <View style={[styles.fixedPlayAllBar, { position: 'absolute', top: STICKY_BAR_HEIGHT, left: 0, right: 0, zIndex: 15, height: PLAY_ALL_BAR_HEIGHT }]}> 
            {renderPlayAllBar()}
          </View>
        )}
        {/* 列表和功能区 */}
        <Animated.FlatList
          ref={flatListRef}
          data={dataWithHeader}
          renderItem={renderItem}
          keyExtractor={(item) => String(item.id)}
          contentContainerStyle={{ paddingBottom: 24, paddingTop: HEADER_MAX_HEIGHT }}
          showsVerticalScrollIndicator={false}
          ListHeaderComponent={renderListHeader()}
          onScroll={Animated.event(
            [{ nativeEvent: { contentOffset: { y: scrollY } } }],
            { useNativeDriver: false }
          )}
          scrollEventThrottle={16}
          onScrollEndDrag={handleScrollEnd}
          onMomentumScrollEnd={handleScrollEnd}
        />
        {/* 头部区（封面、标题、日期） */}
        <Animated.View style={[styles.animatedHeader, { height: headerHeight, position: 'absolute', left: 0, right: 0, top: 0, zIndex: 1, overflow: 'hidden' }]}> 
          <ImageBackground
            source={coverUrl ? { uri: coverUrl } : undefined}
            style={styles.bgImage}
            blurRadius={18}
          >
            <View style={styles.bgOverlay} />
            <SafeAreaView style={{ flex: 1 }}>
              <View style={styles.headerTopRow}>
                <TouchableOpacity style={styles.backButton} onPress={onClose}>
                  <Icon name="arrow-back" size={24} color="#fff" />
                </TouchableOpacity>
                <TouchableOpacity style={styles.menuBtn}>
                  <Icon name="more-vert" size={24} color="#fff" />
                </TouchableOpacity>
              </View>
              <Animated.View style={{ alignItems: 'center', marginTop: 8, opacity: titleOpacity }}>
                {coverUrl && (
                  <Animated.Image
                    source={{ uri: coverUrl }}
                    style={[
                      styles.cover,
                      {
                        transform: [
                          { scale: coverScale },
                          { translateY: coverTranslateY },
                        ],
                      },
                    ]}
                  />
                )}
                <Text style={styles.title}>{title}</Text>
                {showDate && date && <Text style={styles.date}>{date}</Text>}
              </Animated.View>
            </SafeAreaView>
          </ImageBackground>
        </Animated.View>
        <MiniPlayer />
      </View>
    </Modal>
  );
};

const styles = StyleSheet.create({
  modalBg: {
    flex: 1,
    backgroundColor: '#0a1a2a',
  },
  animatedHeader: {
    width: '100%',
    overflow: 'hidden',
    borderBottomLeftRadius: 18,
    borderBottomRightRadius: 18,
  },
  bgImage: {
    flex: 1,
    width: '100%',
    height: '100%',
    justifyContent: 'flex-start',
  },
  bgOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(10,20,40,0.75)',
  },
  headerTopRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingTop: 4,
  },
  backButton: {
    backgroundColor: 'rgba(0,0,0,0.3)',
    borderRadius: 16,
    padding: 4,
  },
  menuBtn: {
    backgroundColor: 'rgba(0,0,0,0.3)',
    borderRadius: 16,
    padding: 4,
  },
  cover: {
    width: COVER_SIZE,
    height: COVER_SIZE,
    borderRadius: 12,
    marginBottom: 8,
    backgroundColor: '#222',
  },
  title: {
    color: '#fff',
    fontSize: 22,
    fontWeight: 'bold',
    marginTop: 8,
  },
  date: {
    color: '#bbb',
    fontSize: 14,
    marginTop: 4,
  },
  playAllBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: '#222b3a',
    borderTopLeftRadius: 18,
    borderTopRightRadius: 18,
    borderBottomLeftRadius: 0,
    borderBottomRightRadius: 0,
    marginHorizontal: 0,
    marginTop: 0,
    height: 48,
    paddingHorizontal: 18,
    boxShadow: '0 2px 8px rgba(0,0,0,0.08)', // web 兼容阴影
  },
  playAllBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(120,180,255,0.18)',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 10,
  },
  playAllText: {
    color: '#fff',
    fontSize: 17,
    fontWeight: 'bold',
  },
  playAllCount: {
    color: '#bbb',
    fontSize: 13,
    marginLeft: 6,
  },
  playAllActions: {
    flexDirection: 'row',
    alignItems: 'center',
    marginLeft: 'auto',
  },
  playAllActionBtn: {
    padding: 6,
    borderRadius: 16,
    backgroundColor: 'rgba(0,0,0,0.08)',
    marginLeft: 8,
  },
  playAllDivider: {
    height: 1,
    backgroundColor: 'rgba(255,255,255,0.05)',
    marginHorizontal: 0,
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#222b3a',
    borderRadius: 0,
    marginHorizontal: 0,
    marginBottom: 0,
    height: 44,
    paddingHorizontal: 18,
  },
  searchInput: {
    flex: 1,
    color: '#fff',
    fontSize: 15,
    paddingHorizontal: 8,
    height: 38,
  },
  songRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 18,
    backgroundColor: 'transparent',
    borderRadius: 12,
  },
  songIndex: {
    color: '#3ec06c',
    width: 24,
    textAlign: 'center',
    fontSize: 17,
    fontWeight: 'bold',
    marginRight: 10,
  },
  songInfoWrap: {
    flex: 1,
    justifyContent: 'center',
  },
  songTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 6,
    letterSpacing: 0.5,
  },
  songSubInfoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 0,
  },
  songFormatBox: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(60,80,120,0.35)',
    borderRadius: 10,
    borderWidth: 1,
    borderColor: '#7ecfff',
    marginRight: 8,
    paddingHorizontal: 8,
    paddingVertical: 2,
  },
  songFormat: {
    color: '#e0f6ff',
    fontSize: 12,
    fontWeight: 'bold',
  },
  songSub: {
    color: '#b0bac6',
    fontSize: 12,
    flexShrink: 1,
    marginLeft: 2,
  },
  songMoreBtn: {
    marginLeft: 10,
    padding: 6,
    borderRadius: 16,
    backgroundColor: 'rgba(0,0,0,0.08)',
  },
  stickyBar: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    zIndex: 10,
    height: HEADER_MIN_HEIGHT,
    backgroundColor: 'rgba(10,20,40,0.98)',
    borderBottomWidth: 0.5,
    borderBottomColor: 'rgba(255,255,255,0.08)',
    justifyContent: 'center',
  },
  stickyBarContent: {
    flexDirection: 'row',
    alignItems: 'center',
    height: HEADER_MIN_HEIGHT,
    paddingHorizontal: 12,
    paddingTop: (StatusBar.currentHeight || 0),
  },
  stickyBackBtn: {
    backgroundColor: 'rgba(0,0,0,0.3)',
    borderRadius: 16,
    padding: 4,
    marginRight: 10,
  },
  stickyMenuBtn: {
    backgroundColor: 'rgba(0,0,0,0.3)',
    borderRadius: 16,
    padding: 4,
    marginLeft: 10,
  },
  stickyBarTitleWrap: {
    flex: 1,
    alignItems: 'center',
  },
  stickyBarTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: 'bold',
  },
  stickyBarDate: {
    color: '#bbb',
    fontSize: 12,
    marginTop: 2,
  },
  fixedPlayAllBar: { backgroundColor: 'transparent' },
});

export default PlaylistDetail;