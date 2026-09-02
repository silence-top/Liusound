import React, { useState, useCallback, useEffect, useRef, memo } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  FlatList,
  Image,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import Icon from 'react-native-vector-icons/MaterialCommunityIcons';
import IconM from 'react-native-vector-icons/MaterialIcons';
import { searchApi } from '../services/navidromeApi';
import { SearchResponse, SongResponse, AlbumResponse, ArtistResponse } from '../types/api';
import { usePlayer } from '../contexts/PlayerContext';
import { useAuth } from '../contexts/AuthContext';
import { buildCoverArtUrl } from '../utils/subsonic';

const SEARCH_DEBOUNCE_MS = 300;

const EMPTY_RESULT: SearchResponse = { songs: [], albums: [], artists: [] };

const SongRow = memo(({
  song,
  coverUrl,
  onPlay,
}: {
  song: SongResponse;
  coverUrl: string;
  onPlay: (song: SongResponse) => void;
}) => (
  <TouchableOpacity style={styles.row} activeOpacity={0.7} onPress={() => onPlay(song)}>
    <Image source={{ uri: coverUrl }} style={styles.rowCover} defaultSource={require('../assets/default-album.png')} />
    <View style={styles.rowInfo}>
      <Text style={styles.rowTitle} numberOfLines={1}>{song.title}</Text>
      <Text style={styles.rowSub} numberOfLines={1}>{song.artist} - {song.album}</Text>
    </View>
    <IconM name="play-circle-outline" size={28} color="#fff" />
  </TouchableOpacity>
));
SongRow.displayName = 'SongRow';

const AlbumRow = memo(({ album, coverUrl }: { album: AlbumResponse; coverUrl: string }) => (
  <View style={styles.row}>
    <Image source={{ uri: coverUrl }} style={styles.rowCover} defaultSource={require('../assets/default-album.png')} />
    <View style={styles.rowInfo}>
      <Text style={styles.rowTitle} numberOfLines={1}>{album.name}</Text>
      <Text style={styles.rowSub} numberOfLines={1}>{album.artist}</Text>
    </View>
  </View>
));
AlbumRow.displayName = 'AlbumRow';

const ArtistRow = memo(({ artist, coverUrl }: { artist: ArtistResponse; coverUrl: string }) => (
  <View style={styles.row}>
    <Image source={{ uri: coverUrl }} style={styles.artistCover} />
    <View style={styles.rowInfo}>
      <Text style={styles.rowTitle} numberOfLines={1}>{artist.name}</Text>
      <Text style={styles.rowSub} numberOfLines={1}>{artist.albumCount} 张专辑 · {artist.songCount} 首</Text>
    </View>
  </View>
));
ArtistRow.displayName = 'ArtistRow';

const SearchScreen = () => {
  const { serverUrl, username, subsonicToken, subsonicSalt } = useAuth();
  const { setCurrentSong } = usePlayer();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResponse | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const getCoverArtUrl = useCallback(
    (id: string) => buildCoverArtUrl({ serverUrl, username, subsonicToken, subsonicSalt }, id),
    [serverUrl, username, subsonicToken, subsonicSalt]
  );

  // 防抖搜索：停止输入 300ms 后请求
  const handleChangeText = useCallback((text: string) => {
    setQuery(text);
    if (debounceRef.current) {
      clearTimeout(debounceRef.current);
      debounceRef.current = null;
    }
    if (!text.trim()) {
      setIsLoading(false);
      setResults(null);
      return;
    }
    setIsLoading(true);
    debounceRef.current = setTimeout(async () => {
      try {
        const response = await searchApi.search(text.trim());
        setResults({
          songs: response.data?.songs ?? [],
          albums: response.data?.albums ?? [],
          artists: response.data?.artists ?? [],
        });
      } catch (error) {
        console.error('Search failed:', error);
        setResults(EMPTY_RESULT);
      } finally {
        setIsLoading(false);
      }
    }, SEARCH_DEBOUNCE_MS);
  }, []);

  // 卸载时清理未触发的防抖任务
  useEffect(() => {
    return () => {
      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
      }
    };
  }, []);

  const handlePlay = useCallback(
    (song: SongResponse) => setCurrentSong(song),
    [setCurrentSong]
  );

  const hasQuery = query.trim().length > 0;
  const isEmpty = results !== null &&
    results.songs.length === 0 && results.albums.length === 0 && results.artists.length === 0;

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.searchContainer}>
        <Icon name="magnify" size={24} color="#666" style={styles.searchIcon} />
        <TextInput
          style={styles.searchInput}
          placeholder="搜索音乐、专辑、艺人"
          placeholderTextColor="#666"
          value={query}
          onChangeText={handleChangeText}
          autoCorrect={false}
          returnKeyType="search"
        />
        {hasQuery && (
          <TouchableOpacity style={styles.clearButton} onPress={() => handleChangeText('')}>
            <Icon name="close-circle" size={20} color="#666" />
          </TouchableOpacity>
        )}
      </View>

      {isLoading && (
        <ActivityIndicator style={styles.loading} size="large" color="#2196F3" />
      )}

      {!isLoading && isEmpty && (
        <View style={styles.emptyContainer}>
          <Icon name="music-off" size={48} color="#444" />
          <Text style={styles.emptyText}>未找到与"{query.trim()}"相关的内容</Text>
        </View>
      )}

      {!isLoading && results && (
        <FlatList
          data={results.songs}
          keyExtractor={item => `song-${item.id}`}
          ListHeaderComponent={
            <View>
              {results.artists.length > 0 && (
                <View style={styles.section}>
                  <Text style={styles.sectionTitle}>艺人</Text>
                  {results.artists.slice(0, 3).map(artist => (
                    <ArtistRow
                      key={artist.id}
                      artist={artist}
                      coverUrl={getCoverArtUrl(artist.id)}
                    />
                  ))}
                </View>
              )}
              {results.albums.length > 0 && (
                <View style={styles.section}>
                  <Text style={styles.sectionTitle}>专辑</Text>
                  {results.albums.slice(0, 5).map(album => (
                    <AlbumRow key={album.id} album={album} coverUrl={getCoverArtUrl(album.id)} />
                  ))}
                </View>
              )}
              {results.songs.length > 0 && (
                <Text style={[styles.sectionTitle, styles.songsSectionTitle]}>歌曲</Text>
              )}
            </View>
          }
          renderItem={({ item }) => (
            <SongRow song={item} coverUrl={getCoverArtUrl(`al-${item.albumId}`)} onPlay={handlePlay} />
          )}
          showsVerticalScrollIndicator={false}
          keyboardShouldPersistTaps="handled"
        />
      )}
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#001B2E',
  },
  searchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    margin: 16,
    paddingHorizontal: 12,
    backgroundColor: '#1a2c3a',
    borderRadius: 8,
  },
  searchIcon: {
    marginRight: 8,
  },
  searchInput: {
    flex: 1,
    height: 44,
    color: '#fff',
    fontSize: 16,
  },
  clearButton: {
    padding: 6,
  },
  loading: {
    marginTop: 40,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingBottom: 80,
  },
  emptyText: {
    color: '#888',
    fontSize: 15,
    marginTop: 12,
  },
  section: {
    marginBottom: 8,
  },
  sectionTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: 'bold',
    marginHorizontal: 16,
    marginTop: 16,
    marginBottom: 8,
  },
  songsSectionTitle: {
    marginTop: 8,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  rowCover: {
    width: 48,
    height: 48,
    borderRadius: 6,
    backgroundColor: '#1a2c3a',
    marginRight: 12,
  },
  artistCover: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: '#1a2c3a',
    marginRight: 12,
  },
  rowInfo: {
    flex: 1,
    marginRight: 8,
  },
  rowTitle: {
    color: '#fff',
    fontSize: 15,
  },
  rowSub: {
    color: '#888',
    fontSize: 13,
    marginTop: 2,
  },
});

export default SearchScreen;
