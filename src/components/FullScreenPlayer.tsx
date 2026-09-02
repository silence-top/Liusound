import React, { useState, useEffect, useMemo, useCallback, useRef } from "react";
import {
  View,
  Text,
  StyleSheet,
  Image,
  TouchableOpacity,
  Dimensions,
  Modal,
  ScrollView,
  Animated,
  Platform,
  View as RNView,
  PanResponder,
  TouchableWithoutFeedback,
  GestureResponderEvent,
} from "react-native";
import Icon from "react-native-vector-icons/MaterialIcons";
import Slider from "@react-native-community/slider";
import { usePlayer } from "../contexts/PlayerContext";
import { useAuth } from "../contexts/AuthContext";
import { songApi } from "../services/navidromeApi";
import { SongResponse } from "../types/api";
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Clipboard from 'expo-clipboard';
import TrackPlayer from 'react-native-track-player-cjx';
import { buildCoverArtUrl } from '../utils/subsonic';
import { storageService } from '../services/config';
import QueueModal from './QueueModal';

const { width } = Dimensions.get("window");

const TAB_TITLES = ["推荐", "歌曲", "歌词"];

const LYRIC_HEIGHT = 48; // 每行歌词的高度（两行）
const LYRIC_LINE_HEIGHT = 36; // 单行歌词高度
const LYRIC_OFFSET_PREFIX = 'lyricOffset_';

// 原生端渐变遮罩：模块级条件 require，避免 web 端加载原生模块
let LinearGradient: any = null;
if (Platform.OS !== 'web') {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  LinearGradient = require('react-native-linear-gradient').default;
}

interface FullScreenPlayerProps {
  visible: boolean;
  onClose: () => void;
}

// 导出清理所有歌词偏移缓存的函数
export const clearAllLyricOffsets = async () => {
  try {
    const keys = await AsyncStorage.getAllKeys();
    const lyricKeys = keys.filter(k => k.startsWith('lyricOffset_'));
    await AsyncStorage.multiRemove(lyricKeys);
    // 可加Toast提示"已清理所有歌词偏移缓存"
  } catch (e) {
    console.error('清理歌词偏移缓存失败', e);
  }
};

const FullScreenPlayer: React.FC<FullScreenPlayerProps> = ({
  visible,
  onClose,
}) => {
  // 所有 useState 放最前面，避免 ReferenceError
  const [showVolume, setShowVolume] = useState(false);
  const [volume, setVolume] = useState(1); // 0~1
  const {
    currentSong,
    isPlaying,
    togglePlay,
    playNext,
    playPrevious,
    setCurrentSong,
    currentTime = 0,
    seekTo,
    lyrics,
    getCurrentLyricIndex,
    audioRef,
    playMode,
    setPlayMode,
  } = usePlayer();
  const { username, subsonicToken, subsonicSalt, serverUrl } = useAuth();
  const [tabIndex, setTabIndex] = useState(1);
  const tabIndexRef = useRef(tabIndex);
  useEffect(() => { tabIndexRef.current = tabIndex; }, [tabIndex]);
  const [recommendSongs, setRecommendSongs] = useState<SongResponse[]>([]);
  const [similarSongs, setSimilarSongs] = useState<SongResponse[]>([]);
  const [isSliderDragging, setIsSliderDragging] = useState(false);
  const [tempCurrentTime, setTempCurrentTime] = useState<number | null>(null);
  const [tempCurrentLyricIndex, setTempCurrentLyricIndex] = useState<number | null>(null);
  const [pendingSeekTime, setPendingSeekTime] = useState<number | null>(null);
  const { height: screenHeight } = Dimensions.get('window');
  const LYRICS_CONTAINER_HEIGHT = screenHeight * 0.6; // 歌词容器高度为屏幕高度的60%
  const lyricScrollViewRef = useRef<ScrollView>(null);
  const scrollViewRef = useRef<ScrollView>(null);
  const [manualScrolling, setManualScrolling] = useState(false);
  const [showLrcMenu, setShowLrcMenu] = useState(false);
  const [showLyricAdjust, setShowLyricAdjust] = useState(false);
  const [lyricOffset, setLyricOffset] = useState(0); // 歌词整体偏移
  // tab切换动画
  const translateX = useRef(new Animated.Value(-tabIndex * width)).current;
  useEffect(() => {
    Animated.timing(translateX, {
      toValue: -tabIndex * width,
      duration: 250,
      useNativeDriver: true,
    }).start();
  }, [tabIndex, translateX]); // width 为模块级常量，无需加入依赖

  const barWidth = 180; // 音量条宽度，与样式保持一致

  // 原生端拖动/点击
  const handleVolumeBarPress = useCallback((evt: GestureResponderEvent) => {
    const { locationX } = evt.nativeEvent;
    let newVolume = locationX / barWidth;
    newVolume = Math.max(0, Math.min(1, newVolume));
    setVolume(newVolume);
    if (Platform.OS === 'web') {
      if (audioRef && audioRef.current) {
        audioRef.current.volume = newVolume;
      } else {
        console.warn('未找到 audioRef.current，无法设置音量');
      }
    } else {
      try {
        const result = TrackPlayer.setVolume?.(newVolume);
        if (result instanceof Promise) {
          result.catch((e: any) => console.warn('TrackPlayer.setVolume 异常', e));
        }
      } catch (e) {
        console.warn('TrackPlayer.setVolume 调用失败', e);
      }
    }
  }, [setVolume, audioRef]);

  // Web端拖拽：用 AbortController 一次性绑定/解绑，避免 handler 间的相互前向引用
  const handleVolumeMouseDown = useCallback((evt: MouseEvent) => {
    evt.stopPropagation();
    evt.preventDefault();
    const el = document.querySelector('#volume-bar');
    if (!el || !('getBoundingClientRect' in el)) return;
    const rect = (el as HTMLElement).getBoundingClientRect();
    const controller = new AbortController();

    const applyVolume = (clientX: number) => {
      let newVolume = (clientX - rect.left) / barWidth;
      newVolume = Math.max(0, Math.min(1, newVolume));
      setVolume(newVolume);
      if (audioRef && audioRef.current) {
        audioRef.current.volume = newVolume;
      }
    };

    const onMouseMove = (moveEvt: MouseEvent) => {
      moveEvt.stopPropagation();
      moveEvt.preventDefault();
      applyVolume(moveEvt.clientX);
    };

    const onMouseUp = (upEvt: MouseEvent) => {
      controller.abort();
      upEvt.stopPropagation();
      upEvt.preventDefault();
    };

    window.addEventListener('mousemove', onMouseMove, { signal: controller.signal });
    window.addEventListener('mouseup', onMouseUp, { signal: controller.signal });
    applyVolume(evt.clientX); // 按下时立即更新一次
  }, [barWidth, audioRef, setVolume]);

  // 复制歌词到剪贴板（必须在所有 useMemo/useEffect/useCallback 之前声明）
  const handleCopyLyrics = useCallback(() => {
    if (!lyrics || lyrics.length === 0) return;
    const text = lyrics.map(l => l.text).join('\n');
    Clipboard.setStringAsync(text);
  }, [lyrics]);

  // 保存歌词偏移（必须在所有 useMemo/useEffect/useCallback 之前声明）
  const handleSaveLyricOffset = useCallback(async () => {
    if (!currentSong) return;
    const key = LYRIC_OFFSET_PREFIX + currentSong.id;
    try {
      if (lyricOffset === 0) {
        await storageService.removeItem(key);
      } else {
        await storageService.setItem(key, lyricOffset.toString());
      }
      setShowLyricAdjust(false); // 保存后关闭工具栏
    } catch (e) {
      console.error('保存歌词偏移失败', e);
    }
  }, [currentSong, lyricOffset]);

  // 切歌时加载已保存的歌词偏移（原先只有保存逻辑，重新打开后偏移丢失）
  const songId = currentSong?.id;
  useEffect(() => {
    if (!songId) return;
    let cancelled = false;
    storageService.getItem(LYRIC_OFFSET_PREFIX + songId)
      .then(saved => {
        if (!cancelled) setLyricOffset(saved !== null ? parseFloat(saved) : 0);
      })
      .catch(() => {
        if (!cancelled) setLyricOffset(0);
      });
    return () => {
      cancelled = true;
    };
  }, [songId]);

  // 使用 useCallback 缓存 getCoverArtUrl 函数（复用共享 Subsonic 工具）
  const getCoverArtUrl = useCallback(
    (id: string) =>
      buildCoverArtUrl({ serverUrl, username, subsonicToken, subsonicSalt }, id),
    [serverUrl, username, subsonicToken, subsonicSalt]
  );

  useEffect(() => {
    if (!currentSong) return;

    // 热门歌曲
    songApi.getSongs({
      _end: 30,
      _order: 'DESC',
      _sort: 'rating',
      _start: 0,
      artist_id: currentSong.artistId,
    }).then(res => {
      setRecommendSongs(res.data || []);
    }).catch(() => setRecommendSongs([]));

    // 相似歌曲
    songApi.getSimilarSongs({
      id: currentSong.id,
      count: 20,
      u: username,
      t: subsonicToken,
      s: subsonicSalt,
      f: 'json',
      v: '1.15.0',
      c: 'Stream Music',
    }).then(res => {
      let songs: SongResponse[] = [];
      if (Array.isArray(res.data?.similarSongs)) {
        songs = res.data.similarSongs;
      } else if (Array.isArray(res.data?.similarSongs?.song)) {
        songs = res.data.similarSongs.song;
      }
      setSimilarSongs(songs);
    }).catch(() => setSimilarSongs([]));
  }, [currentSong, username, subsonicToken, subsonicSalt]);

  // 根据时间获取歌词索引
  const getLyricIndexByTime = useCallback((time: number) => {
    if (!lyrics) return -1;
    for (let i = lyrics.length - 1; i >= 0; i--) {
      if (time >= lyrics[i].time) {
        return i;
      }
    }
    return -1;
  }, [lyrics]);

  // 处理进度条拖动
  const handleSliderStart = useCallback(() => {
    setIsSliderDragging(true);
    setTempCurrentTime(currentTime);
    setTempCurrentLyricIndex(getLyricIndexByTime(currentTime));
  }, [currentTime, getLyricIndexByTime]);

  const getLyricScrollY = useCallback((index: number) => {
    if (!lyrics || lyrics.length === 0) return 0;
    const lyricContentHeight = lyrics.length * LYRIC_HEIGHT;
    const maxScrollY = Math.max(0, lyricContentHeight - LYRICS_CONTAINER_HEIGHT);
    const targetY = index * LYRIC_HEIGHT - (LYRICS_CONTAINER_HEIGHT - LYRIC_HEIGHT) / 2;
    return Math.max(0, Math.min(targetY, maxScrollY));
  }, [lyrics, LYRICS_CONTAINER_HEIGHT]);

  const handleSliderChange = useCallback((value: number) => {
    setTempCurrentTime(value);
    // 根据拖动的时间更新歌词位置和高亮
    if (lyrics && lyricScrollViewRef.current) {
      const index = getLyricIndexByTime(value);
      if (index !== -1) {
        setTempCurrentLyricIndex(index);
        const scrollY = getLyricScrollY(index);
        lyricScrollViewRef.current.scrollTo({
          y: scrollY,
          animated: false
        });
      }
    }
  }, [lyrics, getLyricIndexByTime, getLyricScrollY]);

  const handleSliderEnd = useCallback(async (value: number) => {
    setIsSliderDragging(false);
    setTempCurrentTime(null);
    setTempCurrentLyricIndex(null);
    setPendingSeekTime(value); // 拖拽松开后锁定显示目标进度
    await seekTo(value);
  }, [seekTo]);

  // 监听 currentTime 跟上后清除 pendingSeekTime
  useEffect(() => {
    if (pendingSeekTime !== null && Math.abs(currentTime - pendingSeekTime) < 0.2) {
      setPendingSeekTime(null);
    }
  }, [currentTime, pendingSeekTime]);

  // 统一进度显示逻辑
  const currentLyricTime = useMemo(() => {
    if (isSliderDragging && tempCurrentTime !== null) return tempCurrentTime;
    if (pendingSeekTime !== null) return pendingSeekTime;
    return currentTime;
  }, [isSliderDragging, tempCurrentTime, pendingSeekTime, currentTime]);

  // 计算当前歌词索引（拖动时只用临时值）
  const currentIndex = useMemo(() => {
    if (isSliderDragging && tempCurrentLyricIndex !== null) {
      return tempCurrentLyricIndex;
    }
    // 歌词偏移应用在这里
    return getCurrentLyricIndex(currentLyricTime + lyricOffset);
  }, [isSliderDragging, tempCurrentLyricIndex, getCurrentLyricIndex, currentLyricTime, lyricOffset]);

  // 歌词少时整体居中（首行也居中）
  const lyricContentHeight = (lyrics?.length || 0) * LYRIC_HEIGHT;
  const isLyricShort = lyricContentHeight < LYRICS_CONTAINER_HEIGHT;

  // 歌词自动滚动到当前行 + 切换时整体淡入淡出动画
  useEffect(() => {
    // 拖动时不自动滚动，避免跳动
    if (isSliderDragging) return;
    if (!lyrics || currentIndex < 0) return;
    // 歌词内容高度大于容器时，始终让高亮行居中
    if (!isLyricShort) {
      const targetY = currentIndex * LYRIC_HEIGHT - (LYRICS_CONTAINER_HEIGHT - LYRIC_HEIGHT) / 2;
      if (lyricScrollViewRef.current) {
        lyricScrollViewRef.current.scrollTo({ y: targetY < 0 ? 0 : targetY, animated: true });
      }
    }
  }, [currentIndex, lyrics, LYRICS_CONTAINER_HEIGHT, isSliderDragging, isLyricShort]);

  // 切换到歌词Tab时，强制让高亮歌词居中
  useEffect(() => {
    if (tabIndex === 2 && lyrics && lyrics.length > 0 && currentIndex >= 0) {
      const scrollY = getLyricScrollY(currentIndex);
      if (lyricScrollViewRef.current) {
        lyricScrollViewRef.current.scrollTo({ y: scrollY, animated: false });
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tabIndex, lyricOffset]); // lyricOffset变化时也要触发

  // 初始化时确保歌词居中
  useEffect(() => {
    if (lyrics && lyrics.length > 0 && currentIndex >= 0) {
      const scrollY = getLyricScrollY(currentIndex);
      if (lyricScrollViewRef.current) {
        lyricScrollViewRef.current.scrollTo({ y: scrollY, animated: false });
      }
    }
  }, [lyrics, currentIndex, LYRICS_CONTAINER_HEIGHT, lyricOffset, getLyricScrollY]);

  // 推荐Tab渲染
  const renderRecommendSongs = useMemo(() => {
    return (
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 0, paddingBottom: 24 }} showsVerticalScrollIndicator={false}>
        <View style={styles.recommendSection}>
          <Text style={styles.sectionTitle}>相似歌曲</Text>
          {similarSongs.length === 0 ? (
            <Text style={styles.noDataText}>暂无数据</Text>
          ) : (
            similarSongs.map(song => (
              <View key={song.id} style={styles.songRow}>
                <Image source={{ uri: getCoverArtUrl(song.albumId) }} style={styles.songCover} />
                <View style={styles.songInfo}>
                  <Text style={styles.songTitle}>{song.title}</Text>
                  <Text style={styles.songSub}>{song.artist} - {song.album}</Text>
                </View>
                <TouchableOpacity style={styles.addBtn}>
                  <Icon name="playlist-add" size={22} color="#fff" />
                </TouchableOpacity>
              </View>
            ))
          )}
        </View>
        <View style={styles.recommendSection}>
          <Text style={styles.sectionTitle}>热门歌曲</Text>
          {recommendSongs.length === 0 ? (
            <Text style={styles.noDataText}>暂无推荐</Text>
          ) : (
            recommendSongs.map(song => (
              <TouchableOpacity key={song.id} style={styles.songRow} activeOpacity={0.7} onPress={() => setCurrentSong(song)}>
                <Image source={{ uri: getCoverArtUrl(song.albumId) }} style={styles.songCover} />
                <View style={styles.songInfo}>
                  <Text style={styles.songTitle}>{song.title}</Text>
                  <Text style={styles.songSub}>{song.artist} - {song.album}</Text>
                </View>
                <TouchableOpacity style={styles.addBtn}>
                  <Icon name="playlist-add" size={22} color="#fff" />
                </TouchableOpacity>
              </TouchableOpacity>
            ))
          )}
        </View>
      </ScrollView>
    );
  }, [recommendSongs, similarSongs, getCoverArtUrl, setCurrentSong]);

  // 缓存当前歌曲信息的渲染
  const renderCurrentSong = useMemo(() => {
    if (!currentSong) return null;

    return (
      <View style={styles.artworkContainer}>
        <Image
          source={{ uri: getCoverArtUrl(currentSong.albumId) }}
          style={styles.artwork}
          defaultSource={require("../assets/default-album.png")}
        />
        <View style={styles.infoContainer}>
          <Text style={styles.songTitle} numberOfLines={2}>
            {currentSong.title}
          </Text>
          <Text style={styles.artistName} numberOfLines={1}>
            {currentSong.artist}
          </Text>
        </View>
      </View>
    );
  }, [currentSong, getCoverArtUrl]);


  // 格式化时间 mm:ss
  const formatTime = (sec: number) => {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return `${m}:${s.toString().padStart(2, '0')}`;
  };


  // 歌词点击跳转
  const handleLyricPress = useCallback((index: number) => {
    if (!lyrics || !lyrics[index]) return;
    seekTo(lyrics[index].time - lyricOffset); // 跳转时减去偏移
  }, [lyrics, seekTo, lyricOffset]);

  // 计算歌词滚动位置
  const calculateScrollPosition = useCallback((index: number) => {
    if (!lyrics || !lyrics.length || index < 0) return 0;

    // 计算当前行到顶部的距离（包含padding）
    const targetY = index * LYRIC_LINE_HEIGHT;

    return targetY;
  }, [lyrics]);

  // 计算歌词容器的padding，确保第一行和最后一行也能居中显示
  const getLyricsPadding = useCallback(() => {
    return {
      paddingTop: LYRICS_CONTAINER_HEIGHT / 2,
      paddingBottom: LYRICS_CONTAINER_HEIGHT / 2
    };
  }, [LYRICS_CONTAINER_HEIGHT]);

  // 处理自动滚动
  useEffect(() => {
    if (!lyrics || currentIndex < 0 || manualScrolling || isSliderDragging) return;

    const targetY = calculateScrollPosition(currentIndex);
    scrollViewRef.current?.scrollTo({
      y: targetY,
      animated: true
    });
  }, [currentIndex, lyrics, manualScrolling, isSliderDragging, calculateScrollPosition]);

  // 处理手动滚动
  const handleScrollBeginDrag = useCallback(() => {
    setManualScrolling(true);
  }, []);

  const handleScrollEndDrag = useCallback(() => {
    // 松手后2秒恢复自动滚动
    setTimeout(() => {
      setManualScrolling(false);
    }, 2000);
  }, []);

  // 重构歌词渲染逻辑
  const renderLyrics = useMemo(() => {
    if (!lyrics || lyrics.length === 0) {
      return (
        <View style={styles.centerContainer}>
          <Text style={styles.loadingText}>暂无歌词</Text>
        </View>
      );
    }

    const { paddingTop, paddingBottom } = getLyricsPadding();

    return (
      <View style={{ flex: 1, position: 'relative' }}>
        <View style={styles.lyricsContainer}>
          <ScrollView
            ref={scrollViewRef}
            style={styles.lyricsScrollView}
            contentContainerStyle={[
              styles.lyricsContent,
              { paddingTop, paddingBottom }
            ]}
            showsVerticalScrollIndicator={false}
            onScrollBeginDrag={handleScrollBeginDrag}
            onScrollEndDrag={handleScrollEndDrag}
            scrollEventThrottle={16}
            overScrollMode="never"
            bounces={false}
          >
            {lyrics.map((lyric, index) => (
              <TouchableOpacity
                key={index}
                style={[
                  styles.lyricLine,
                  { height: LYRIC_LINE_HEIGHT }
                ]}
                onPress={() => handleLyricPress(index)}
                activeOpacity={0.7}
              >
                <Text
                  style={[
                    styles.lyricText,
                    index === currentIndex && styles.currentLyricText,
                  ]}
                  numberOfLines={1}
                >
                  {lyric.text}
                </Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
          {/* 顶部和底部渐变遮罩，底部渐变放在歌词内容和按钮之间 */}
          {Platform.OS === 'web' ? (
            <>
              {/* @ts-ignore */}
              <RNView style={[styles.lyricFadeTop, { height: '30%', backgroundImage: 'linear-gradient(to bottom, rgba(10,20,40,0.93), transparent)' }]} />
              {/* @ts-ignore */}
              <RNView style={[styles.lyricFadeBottom, { height: '30%', backgroundImage: 'linear-gradient(to top, rgba(10,20,40,0.93), transparent)' }]} />
            </>
          ) : (
            LinearGradient && <>
              <LinearGradient
                colors={["#0a1428ee", "transparent"]}
                style={[styles.lyricFadeTop, { height: '30%' }]}
                pointerEvents="none"
              />
              <LinearGradient
                colors={["transparent", "#0a1428ee"]}
                style={[styles.lyricFadeBottom, { height: '30%' }]}
                pointerEvents="none"
              />
            </>
          )}
        </View>
      </View>
    );
  }, [lyrics, currentIndex, getLyricsPadding, handleLyricPress, handleScrollBeginDrag, handleScrollEndDrag]);

  // 打开时立即滚动到当前歌词高亮行
  useEffect(() => {
    if (visible && lyrics && lyrics.length > 0 && currentIndex >= 0) {
      const targetY = calculateScrollPosition(currentIndex);
      scrollViewRef.current?.scrollTo({
        y: targetY,
        animated: false, // 立即跳转
      });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible]);

  // 滑动切换tab
  const panResponder = useRef(
    PanResponder.create({
      onMoveShouldSetPanResponder: (evt, gestureState) => {
        return Math.abs(gestureState.dx) > 20 && Math.abs(gestureState.dy) < 20;
      },
      onPanResponderRelease: (evt, gestureState) => {
        const idx = tabIndexRef.current;
        if (gestureState.dx < -40 && idx < 2) {
          setTabIndex(idx + 1);
        } else if (gestureState.dx > 40 && idx > 0) {
          setTabIndex(idx - 1);
        }
      },
    })
  ).current;

  const [showQueueModal, setShowQueueModal] = useState(false);

  // 播放模式切换
  const playModeIcon = useMemo(() => {
    if (playMode === 'shuffle') return 'shuffle';
    if (playMode === 'repeat-one') return 'repeat-one';
    return 'repeat';
  }, [playMode]);
  const handleSwitchPlayMode = useCallback(() => {
    if (playMode === 'order') setPlayMode('shuffle');
    else if (playMode === 'shuffle') setPlayMode('repeat-one');
    else setPlayMode('order');
  }, [playMode, setPlayMode]);

  // 当前歌曲被移除时自动关闭播放器（不能在 render 期间调用 onClose，
  // 否则属于 setState during render 反模式，可能引发告警或死循环）
  useEffect(() => {
    if (visible && !currentSong) {
      onClose();
    }
  }, [visible, currentSong, onClose]);

  if (!currentSong) {
    return null;
  }

  return (
    <Modal
      visible={visible}
      transparent={true}
      animationType="slide"
      onRequestClose={onClose}
    >
      <View style={styles.container}>
        {/* 外层加顶部padding，headerWrapper本身不加paddingTop */}
        <View style={{ paddingTop: 16 }}>
          <View style={styles.headerWrapper}>
            <TouchableOpacity onPress={onClose} style={styles.backBtn}>
              <Icon name="keyboard-arrow-down" size={32} color="#fff" />
            </TouchableOpacity>
            <View style={styles.tabBarAbsoluteCenter} pointerEvents="box-none">
              <View style={styles.tabBarRow}>
                {TAB_TITLES.map((title, idx) => (
                  <TouchableOpacity
                    key={title}
                    style={styles.tabItem}
                    onPress={() => setTabIndex(idx)}
                  >
                    <Text
                      style={[
                        styles.tabText,
                        tabIndex === idx && styles.tabTextActive,
                      ]}
                    >
                      {title}
                    </Text>
                  </TouchableOpacity>
                ))}
              </View>
            </View>
          </View>
        </View>

        {/* Tab内容区 - 保持所有Tab内容挂载，切换仅隐藏显示，避免图片等重复加载 */}
        <View style={styles.tabContent} {...panResponder.panHandlers}>
          <Animated.View style={{ flexDirection: 'row', width: width * 3, flex: 1, transform: [{ translateX }] }}>
            <View style={{ width, flex: 1 }}>
              {renderRecommendSongs}
            </View>
            <View style={{ width, flex: 1 }}>
              <View style={styles.centerContainer}>
                {renderCurrentSong}
              </View>
            </View>
            <View style={{ width, flex: 1 }}>
              {renderLyrics}
              {/* LRC和音量按钮区：无论有无歌词都显示音量按钮，有歌词时显示LRC按钮 */}
              <View style={styles.lrcRow}>
                {lyrics && lyrics.length > 0 && (
                  <>
                    {/* LRC 弹出菜单 */}
                    {showLrcMenu && (
                      <TouchableOpacity
                        style={styles.lrcMenuMask}
                        activeOpacity={1}
                        onPress={() => setShowLrcMenu(false)}
                      >
                        <View style={styles.lrcMenu}>
                          <TouchableOpacity style={styles.lrcMenuItem} onPress={() => { setShowLrcMenu(false); setShowLyricAdjust(true); }}>
                            <Icon name="tune" size={18} color="#fff" style={styles.lrcMenuIcon} />
                            <Text style={styles.lrcMenuText}>调整歌词</Text>
                          </TouchableOpacity>
                          <TouchableOpacity style={styles.lrcMenuItem} onPress={() => setShowLrcMenu(false)}>
                            <Icon name="translate" size={18} color="#fff" style={styles.lrcMenuIcon} />
                            <Text style={styles.lrcMenuText}>生成翻译</Text>
                          </TouchableOpacity>
                          <TouchableOpacity style={styles.lrcMenuItem} onPress={() => setShowLrcMenu(false)}>
                            <Icon name="search" size={18} color="#fff" style={styles.lrcMenuIcon} />
                            <Text style={styles.lrcMenuText}>切换歌词</Text>
                          </TouchableOpacity>
                        </View>
                      </TouchableOpacity>
                    )}
                    <TouchableOpacity style={styles.lrcBtn} onPress={() => setShowLrcMenu(true)}>
                      <Text style={{ color: '#fff', fontSize: 13 }}>LRC</Text>
                    </TouchableOpacity>
                  </>
                )}
                {/* 音量按钮和音量条始终显示 */}
                <TouchableOpacity onPress={() => setShowVolume(v => !v)}>
                  <Icon name="volume-up" size={20} color="#fff" />
                </TouchableOpacity>
                {showVolume && (
                  <View style={{ position: 'absolute', left: lyrics && lyrics.length > 0 ? 70 : 30, bottom: 0, zIndex: 100 }}>
                    {/* 遮罩层，点击遮罩关闭音量条 */}
                    <TouchableWithoutFeedback onPress={() => setShowVolume(false)}>
                      <View style={{
                        position: 'absolute',
                        left: 0,
                        top: 0,
                        width,
                        height: screenHeight,
                        zIndex: 99,
                      }} />
                    </TouchableWithoutFeedback>
                    {/* 音量条本体，点击不会关闭 */}
                    <View
                      id={Platform.OS === 'web' ? 'volume-bar' : undefined}
                      style={[styles.volumeBarWrap, Platform.OS === 'web' ? { cursor: 'pointer' } : null, { zIndex: 100 }]}
                      {...(Platform.OS === 'web'
                        ? { onMouseDown: (e: any) => handleVolumeMouseDown(e.nativeEvent) }
                        : {
                            onStartShouldSetResponder: () => true,
                            onResponderGrant: handleVolumeBarPress,
                            onResponderMove: handleVolumeBarPress,
                          })}
                    >
                      {/* 白色进度条背景 */}
                      <View style={[styles.volumeBarProgress, { width: `${Math.max(8, volume * 100)}%` }]} />
                      {/* 内容层 */}
                      <View style={styles.volumeBarContent} pointerEvents="none">
                        <Icon name="volume-up" size={22} color={volume > 0.5 ? '#222' : '#888'} style={{ marginRight: 8 }} />
                        <Text style={[styles.volumePercentCustom, { color: volume > 0.5 ? '#222' : '#fff' }]}>{Math.round(volume * 100)}%</Text>
                      </View>
                    </View>
                  </View>
                )}
              </View>
              {/* 歌词区右侧整体调整浮层 */}
              {showLyricAdjust && (
                <View style={styles.lyricAdjustPanel}>
                  <TouchableOpacity style={styles.lyricAdjustBtn} onPress={() => setLyricOffset(v => parseFloat((v + 0.05).toFixed(2)))}>
                    <Icon name="arrow-upward" size={22} color="#fff" />
                  </TouchableOpacity>
                  <Text style={styles.lyricAdjustTime}>{lyricOffset.toFixed(2)}s</Text>
                  <TouchableOpacity style={styles.lyricAdjustBtn} onPress={() => setLyricOffset(v => parseFloat((v - 0.05).toFixed(2)))}>
                    <Icon name="arrow-downward" size={22} color="#fff" />
                  </TouchableOpacity>
                  <TouchableOpacity style={styles.lyricAdjustBtn} onPress={() => setLyricOffset(0)}>
                    <Icon name="refresh" size={22} color="#fff" />
                  </TouchableOpacity>
                  <TouchableOpacity style={styles.lyricAdjustBtn} onPress={handleSaveLyricOffset}>
                    <Icon name="check" size={22} color="#fff" />
                  </TouchableOpacity>
                  <TouchableOpacity style={styles.lyricAdjustBtn} onPress={handleCopyLyrics}>
                    <Icon name="content-copy" size={22} color="#fff" />
                  </TouchableOpacity>
                </View>
              )}
            </View>
          </Animated.View>
        </View>

        <View style={styles.bottomArea}>
          {/* 歌曲信息行 */}
          <View style={styles.songInfoRow}>
            <View style={{ flex: 1 }}>
              <Text style={styles.songTitleInfo} numberOfLines={1}>{currentSong?.title || ''}</Text>
              <Text style={styles.songSubTitleInfo} numberOfLines={1}>{currentSong ? `${currentSong.artist} - ${currentSong.album}` : ''}</Text>
            </View>
            <View style={styles.songInfoActions}>
              <TouchableOpacity style={styles.iconBtn}>
                <Icon name="favorite-border" size={22} color="#fff" />
              </TouchableOpacity>
              <TouchableOpacity style={styles.iconBtn}>
                <Icon name="more-vert" size={22} color="#fff" />
              </TouchableOpacity>
            </View>
          </View>

          {/* 进度条行 */}
          <View style={styles.progressRow}>
            <Slider
              style={styles.progressBarCustom}
              minimumValue={0}
              maximumValue={currentSong?.duration || 1}
              value={currentLyricTime}
              onSlidingStart={handleSliderStart}
              onValueChange={handleSliderChange}
              onSlidingComplete={handleSliderEnd}
              tapToSeek={true}
              minimumTrackTintColor="#fff"
              maximumTrackTintColor="#444"
              thumbTintColor="#fff"
            />
          </View>
          <View style={styles.timeRow}>
            <Text style={styles.timeText}>{formatTime(currentLyricTime)}</Text>
            <Text style={styles.timeText}>{formatTime(currentSong?.duration || 0)}</Text>
          </View>

          {/* 控制按钮行 */}
          <View style={styles.controlsRow}>
            <TouchableOpacity style={styles.iconBtn} onPress={handleSwitchPlayMode}>
              <Icon name={playModeIcon} size={24} color="#fff" />
              {/* 可选：显示模式名 */}
              {/* <Text style={{color:'#fff',fontSize:10,marginTop:2}}>{playModeText}</Text> */}
            </TouchableOpacity>
            <TouchableOpacity style={styles.iconBtn} onPress={playPrevious}>
              <Icon name="skip-previous" size={28} color="#fff" />
            </TouchableOpacity>
            <TouchableOpacity style={styles.playPauseBtn} onPress={togglePlay}>
              <Icon
                name={isPlaying ? "pause" : "play-arrow"}
                size={36}
                color="#fff"
              />
            </TouchableOpacity>
            <TouchableOpacity style={styles.iconBtn} onPress={playNext}>
              <Icon name="skip-next" size={28} color="#fff" />
            </TouchableOpacity>
            <TouchableOpacity style={styles.iconBtn} onPress={() => setShowQueueModal(true)}>
              <Icon name="queue-music" size={24} color="#fff" />
            </TouchableOpacity>
          </View>
        </View>

        <QueueModal visible={showQueueModal} onClose={() => setShowQueueModal(false)} />
      </View>
    </Modal>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#0a1428",
  },
  headerWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    width: '100%',
    height: 48,
    position: 'relative',
  },
  backBtn: {
    paddingHorizontal: 8,
    height: 48,
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 2,
  },
  tabBarAbsoluteCenter: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 1,
    height: 48,
    pointerEvents: 'box-none',
  },
  tabBarRow: {
    flexDirection: 'row',
    height: 48,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 8,
  },
  tabItem: {
    paddingHorizontal: 18,
    paddingVertical: 6,
    alignItems: 'center',
    justifyContent: 'center',
  },
  tabText: {
    color: '#888',
    fontSize: 16,
    fontWeight: '400',
  },
  tabTextActive: {
    color: '#fff',
    fontWeight: 'bold',
  },
  tabContent: {
    flex: 1,
  },
  centerContainer: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
  },
  loadingText: {
    color: "#888",
    fontSize: 16,
  },
  recommendSection: {
    marginBottom: 28,
    paddingHorizontal: 18,
  },
  sectionTitle: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 8,
    marginLeft: 12,
  },
  noDataText: {
    color: '#888',
    fontSize: 14,
    marginBottom: 12,
    marginLeft: 12,
  },
  songRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 14,
    marginLeft: 12,
    marginRight: 12,
  },
  songCover: {
    width: 44,
    height: 44,
    borderRadius: 4,
    marginRight: 12,
    backgroundColor: '#222',
  },
  songInfo: {
    flex: 1,
  },
  songTitle: {
    color: '#fff',
    fontSize: 15,
  },
  songSub: {
    color: '#aaa',
    fontSize: 13,
    marginTop: 2,
  },
  addBtn: {
    padding: 6,
  },
  artworkContainer: {
    alignItems: "center",
    marginBottom: 32,
  },
  artwork: {
    width: width * 0.8,
    height: width * 0.8,
    borderRadius: 8,
    marginBottom: 24,
  },
  infoContainer: {
    alignItems: "center",
  },
  songTitleInfo: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 2,
  },
  songSubTitleInfo: {
    color: '#aaa',
    fontSize: 13,
  },
  songInfoActions: {
    flexDirection: 'row',
    alignItems: 'center',
    marginLeft: 8,
  },
  iconBtn: {
    padding: 6,
    marginLeft: 2,
  },
  progressRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    marginTop: 2,
    marginBottom: 4,
  },
  progressBarCustom: {
    flex: 1,
    height: 24,
    marginHorizontal: 8,
  },
  sliderThumb: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: '#fff',
  },
  timeRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 12,
    marginBottom: 16,
  },
  timeText: {
    color: '#aaa',
    fontSize: 12,
    width: 38,
    textAlign: 'center',
  },
  controlsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 24,
    marginTop: 8,
    marginBottom: 8,
  },
  playPauseBtn: {
    width: 56,
    height: 56,
    borderRadius: 28,
    borderWidth: 2,
    borderColor: '#fff',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.08)',
    marginHorizontal: 8,
  },
  lyricsContainer: {
    flex: 1,
    width: '100%',
  },
  lyricsScrollView: {
    flex: 1,
  },
  lyricsContent: {
    width: '100%',
  },
  lyricLine: {
    width: '100%',
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 20,
  },
  lyricText: {
    fontSize: 16,
    color: 'rgba(255, 255, 255, 0.5)',
    textAlign: 'center',
  },
  currentLyricText: {
    fontSize: 18,
    color: '#fff',
    fontWeight: '600',
  },
  bottomArea: {
    marginBottom: 20,
  },
  lrcRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginLeft: 28,
    height:36,
    marginTop: 8,
    marginBottom: 6,
    position: 'relative',
  },
  lrcBtn: {
    borderWidth: 1,
    borderColor: '#fff',
    borderRadius: 4,
    paddingHorizontal: 8,
    paddingVertical: 2,
    marginRight: 8,
  },
  lyricFadeTop: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    height: '20%',
    zIndex: 10,
    pointerEvents: 'none',
  },
  lyricFadeBottom: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    height: '15%',
    zIndex: 10,
    pointerEvents: 'none',
  },
  lrcMenuMask: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    top: 0,
    zIndex: 200,
  },
  lrcMenu: {
    position: 'absolute',
    left: 0,
    bottom: 40,
    backgroundColor: 'rgba(30,30,30,0.96)',
    borderRadius: 10,
    paddingVertical: 6,
    minWidth: 140,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 8,
    elevation: 8,
    zIndex: 201,
  },
  lrcMenuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 16,
  },
  lrcMenuIcon: {
    marginRight: 12,
  },
  lrcMenuText: {
    color: '#fff',
    fontSize: 15,
  },
  lyricAdjustPanel: {
    position: 'absolute',
    right: 18,
    top: '18%',
    width: 56,
    borderRadius: 12,
    backgroundColor: 'rgba(30,30,30,0.85)',
    alignItems: 'center',
    paddingVertical: 18,
    zIndex: 100,
  },
  lyricAdjustBtn: {
    marginVertical: 8,
    padding: 6,
    borderRadius: 8,
  },
  lyricAdjustTime: {
    color: '#fff',
    fontSize: 14,
    marginVertical: 8,
  },
  artistName: {
    color: "#888",
    fontSize: 16,
  },
  songInfoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    marginTop: 8,
    marginBottom: 16,
    marginLeft: 8,
    marginRight: 8,
  },
  volumeBarWrap: {
    flexDirection: 'row',
    borderRadius: 16,
    overflow: 'hidden',
    width: 180,
    height:36,
    backgroundColor: '#222',
    alignItems: 'center',
    position: 'relative',
  },
  volumeBarProgress: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: 0,
    backgroundColor: '#fff',
    borderRadius: 16,
    zIndex: 0,
  },
  volumeBarContent: {
    flexDirection: 'row',
    alignItems: 'center',
    width: '100%',
    height: '100%',
    zIndex: 1,
    paddingHorizontal: 8,
  },
  volumeSliderCustom: {
    flex: 1,
    height: 36,
    marginHorizontal: 4,
  },
  volumePercentCustom: {
    fontSize: 15,
    marginLeft: 8,
    width: 40,
    textAlign: 'right',
    fontWeight: 'bold',
  },
});

export default FullScreenPlayer;
