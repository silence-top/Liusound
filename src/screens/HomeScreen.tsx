import React, { useEffect, useState, useCallback, memo } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  Image,
  TouchableOpacity,
  FlatList,
  ActivityIndicator,
  RefreshControl,
  TextInput,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { albumApi, songApi } from '../services/navidromeApi';
import { AlbumResponse, SongResponse } from '../types/api';
import { useAuth } from '../contexts/AuthContext';
import Icon from 'react-native-vector-icons/MaterialIcons';
import { usePlayer } from '../contexts/PlayerContext';
import { buildCoverArtUrl } from '../utils/subsonic';
import PlaylistDetail from '../components/PlaylistDetail';

/** 生成随机 seed：使 Navidrome 的 random 排序在每次刷新时真正随机 */
const makeSeed = () => `${Math.random()}-${Date.now()}`;

const AlbumItem = memo(({ item, getCoverArtUrl }: { item: AlbumResponse; getCoverArtUrl: (id: string) => string }) => (
  <TouchableOpacity style={styles.albumCard}>
    <Image
      source={{ uri: getCoverArtUrl(item.id) }}
      style={styles.albumCover}
      defaultSource={require('../assets/default-album.png')}
    />
    <Text style={styles.albumTitle} numberOfLines={1}>
      {item.name}
    </Text>
    <Text style={styles.albumArtist} numberOfLines={1}>
      {item.artist}
    </Text>
  </TouchableOpacity>
));
AlbumItem.displayName = 'AlbumItem';

const SongItem = memo(({ item, getCoverArtUrl, onPlay }: { 
  item: SongResponse; 
  getCoverArtUrl: (id: string) => string;
  onPlay: (song: SongResponse) => void;
}) => (
  <View style={styles.recommendItem}>
    <Image
      source={{ uri: getCoverArtUrl(`al-${item.albumId}`) }}
      style={styles.recommendCover}
      defaultSource={require('../assets/default-album.png')}
    />
    <View style={styles.recommendInfo}>
      <Text style={styles.recommendTitle} numberOfLines={1}>{item.title}</Text>
      <Text style={styles.recommendSub} numberOfLines={1}>{item.artist} - {item.album}</Text>
    </View>
    <TouchableOpacity style={styles.recommendPlayBtn} onPress={() => onPlay(item)}>
      <Icon name="play-circle-outline" size={32} color="#fff" />
    </TouchableOpacity>
  </View>
));
SongItem.displayName = 'SongItem';

const HomeScreen = () => {
  // serverUrl 直接取自 AuthContext，避免重复从 AsyncStorage 读取
  const { username, subsonicToken, subsonicSalt, serverUrl } = useAuth();
  const [latestAlbums, setLatestAlbums] = useState<AlbumResponse[]>([]);
  const [recentlyPlayed, setRecentlyPlayed] = useState<AlbumResponse[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dailyRecommend, setDailyRecommend] = useState<SongResponse[]>([]);
  const [mostPlayed, setMostPlayed] = useState<AlbumResponse[]>([]);
  const [randomAlbums, setRandomAlbums] = useState<AlbumResponse[]>([]);
  const { setCurrentSong } = usePlayer();
  const [showDailyRecommendDetail, setShowDailyRecommendDetail] = useState(false);

  // 封面地址（复用共享 Subsonic 工具）
  const getCoverArtUrl = useCallback(
    (id: string) =>
      buildCoverArtUrl({ serverUrl, username, subsonicToken, subsonicSalt }, id),
    [serverUrl, username, subsonicToken, subsonicSalt]
  );

  const loadData = useCallback(async () => {
    try {
      setError(null);
      const [albumsResponse, recentlyPlayedResponse, mostPlayedResponse, randomAlbumsResponse, dailyRecommendResponse] = await Promise.all([
        albumApi.getAlbums({
          _end: 20,
          _order: 'DESC',
          _sort: 'recently_added',
          _start: 0,
        }),
        albumApi.getAlbums({
          _end: 20,
          _order: 'DESC',
          _sort: 'play_date',
          _start: 0,
          recently_played: true,
        }),
        albumApi.getAlbums({
          _end: 20,
          _order: 'DESC',
          _sort: 'play_count',
          _start: 0,
        }),
        albumApi.getAlbums({
          _end: 20,
          _order: 'ASC',
          _sort: 'random',
          _start: 0,
          seed: makeSeed(),
        }),
        songApi.getSongs({
          _end: 50,
          _order: 'ASC',
          _sort: 'random',
          _start: 0,
        })
      ]);

      setLatestAlbums(albumsResponse.data || []);
      setRecentlyPlayed(recentlyPlayedResponse.data || []);
      setMostPlayed(mostPlayedResponse.data || []);
      setRandomAlbums(randomAlbumsResponse.data || []);
      setDailyRecommend(dailyRecommendResponse.data || []);
    } catch (err) {
      setError('加载数据失败，请稍后重试');
      console.error('Failed to load home data:', err);
    }
  }, []);

  const handleRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await loadData();
    setIsRefreshing(false);
  }, [loadData]);

  const handlePlay = useCallback((song: SongResponse) => {
    setCurrentSong(song);
  }, [setCurrentSong]);

  useEffect(() => {
    const initializeData = async () => {
      await loadData();
      setIsLoading(false);
    };
    initializeData();
  }, [loadData]);

  const renderAlbumItem = useCallback(({ item }: { item: AlbumResponse }) => (
    <AlbumItem item={item} getCoverArtUrl={getCoverArtUrl} />
  ), [getCoverArtUrl]);

  const renderSongItem = useCallback(({ item }: { item: SongResponse }) => (
    <SongItem item={item} getCoverArtUrl={getCoverArtUrl} onPlay={handlePlay} />
  ), [getCoverArtUrl, handlePlay]);

  const keyExtractor = useCallback((item: AlbumResponse | SongResponse) => item.id, []);

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color="#2196F3" />
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.errorContainer}>
        <Text style={styles.errorText}>{error}</Text>
        <TouchableOpacity style={styles.retryButton} onPress={loadData}>
          <Text style={styles.retryButtonText}>重试</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      {/* 搜索栏 */}
      <View style={styles.searchBar}>
        <Icon name="search" size={20} color="#888" style={{ marginLeft: 8 }} />
        <TextInput
          style={styles.searchInput}
          placeholder="搜索"
          placeholderTextColor="#aaa"
        />
        <Icon name="qr-code" size={20} color="#888" style={{ marginRight: 8 }} />
      </View>
      <ScrollView
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={handleRefresh}
            tintColor="#2196F3"
          />
        }
      >
        {/* 最新专辑 */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>最新专辑</Text>
          </View>
          <FlatList
            data={latestAlbums}
            renderItem={renderAlbumItem}
            keyExtractor={keyExtractor}
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.albumList}
          />
        </View>
        {/* 每日推荐 */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>每日推荐</Text>
            <TouchableOpacity onPress={() => setShowDailyRecommendDetail(true)}>
              <Text style={styles.seeMore}>查看更多</Text>
            </TouchableOpacity>
          </View>
          <FlatList
            data={dailyRecommend.slice(0, 3)}
            renderItem={renderSongItem}
            keyExtractor={keyExtractor}
            showsVerticalScrollIndicator={false}
            scrollEnabled={false}
            contentContainerStyle={styles.recommendList}
          />
        </View>
        {/* 最近播放 */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>最近播放</Text>
          </View>
          <FlatList
            data={recentlyPlayed}
            renderItem={renderAlbumItem}
            keyExtractor={keyExtractor}
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.albumList}
          />
        </View>
        {/* 最常播放 */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>最常播放</Text>
          </View>
          <FlatList
            data={mostPlayed}
            renderItem={renderAlbumItem}
            keyExtractor={keyExtractor}
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.albumList}
          />
        </View>
        {/* 随机专辑 */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>随机专辑</Text>
          </View>
          <FlatList
            data={randomAlbums}
            renderItem={renderAlbumItem}
            keyExtractor={keyExtractor}
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.albumList}
          />
        </View>
      </ScrollView>
      <PlaylistDetail
        visible={showDailyRecommendDetail}
        onClose={() => setShowDailyRecommendDetail(false)}
        songs={dailyRecommend}
        title="每日推荐"
        coverUrl={getCoverArtUrl(`al-${dailyRecommend[0]?.albumId || ''}`)}
        date={new Date().toISOString().slice(0, 10)}
        showDate={true}
        showActions={true}
      />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#001B2E',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#001B2E',
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#001B2E',
    padding: 20,
  },
  errorText: {
    color: '#fff',
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 20,
  },
  retryButton: {
    backgroundColor: '#2196F3',
    padding: 12,
    borderRadius: 8,
  },
  retryButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  section: {
    marginBottom: 24,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: 12,
  },
  sectionTitle: {
    color: '#fff',
    fontSize: 20,
    fontWeight: 'bold',
  },
  albumList: {
    paddingHorizontal: 12,
  },
  albumCard: {
    width: 140,
    marginHorizontal: 4,
  },
  albumCover: {
    width: 140,
    height: 140,
    borderRadius: 8,
    marginBottom: 8,
    backgroundColor: '#1a2c3a',
  },
  albumTitle: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '500',
  },
  albumArtist: {
    color: '#666',
    fontSize: 12,
    marginTop: 4,
  },
  songList: {
    paddingHorizontal: 16,
  },
  songItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
  },
  songCover: {
    width: 56,
    height: 56,
    borderRadius: 4,
    backgroundColor: '#1a2c3a',
  },
  songInfo: {
    flex: 1,
    marginLeft: 12,
  },
  songTitle: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '500',
  },
  songArtist: {
    color: '#666',
    fontSize: 14,
    marginTop: 4,
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#13304a',
    borderRadius: 20,
    marginHorizontal: 16,
    marginBottom: 8,
    height: 38,
  },
  searchInput: {
    flex: 1,
    color: '#fff',
    fontSize: 16,
    paddingHorizontal: 8,
    height: 38,
  },
  recommendList: {
    paddingHorizontal: 16,
  },
  recommendItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 18,
  },
  recommendCover: {
    width: 56,
    height: 56,
    borderRadius: 8,
    backgroundColor: '#1a2c3a',
  },
  recommendInfo: {
    flex: 1,
    marginLeft: 14,
    justifyContent: 'center',
  },
  recommendTitle: {
    color: '#fff',
    fontSize: 17,
    fontWeight: 'bold',
  },
  recommendSub: {
    color: '#b0b0b0',
    fontSize: 14,
    marginTop: 4,
  },
  recommendPlayBtn: {
    marginLeft: 12,
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalContainer: {
    flex: 1,
    backgroundColor: '#001B2E',
  },
  modalHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    backgroundColor: '#1a1a1a',
  },
  backButton: {
    marginRight: 16,
  },
  modalTitle: {
    color: '#fff',
    fontSize: 20,
    fontWeight: 'bold',
  },
  modalList: {
    padding: 16,
  },
  dailyRecommend: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1a2c3a',
    borderRadius: 8,
    padding: 12,
  },
  dailyRecommendCover: {
    width: 100,
    height: 100,
    borderRadius: 4,
    marginRight: 12,
  },
  dailyRecommendInfo: {
    flex: 1,
  },
  dailyRecommendTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: 'bold',
  },
  dailyRecommendDate: {
    color: '#b0b0b0',
    fontSize: 14,
  },
  seeMore: {
    color: '#2196F3',
    fontSize: 14,
    fontWeight: 'bold',
  },
});

export default memo(HomeScreen); 