import React, { createContext, useContext, useState, useRef, useCallback, useEffect, ReactNode } from 'react';
import TrackPlayer, {
  State,
  Event,
  Capability
} from 'react-native-track-player-cjx';
import { Platform } from 'react-native';
import axios from 'axios';

import { SongResponse } from '../types/api';
import { useAuth } from './AuthContext';
import { STORAGE_KEYS, storageService } from '../services/config';
import {
  buildCoverArtUrl,
  buildStreamUrl,
  buildSubsonicParams,
  SubsonicAuth,
} from '../utils/subsonic';

interface LyricLine {
  start: number;
  value: string;
}

interface LyricData {
  lang: string;
  line: LyricLine[];
  synced: boolean;
}

export interface Lyric {
  time: number;
  text: string;
}

type PlayMode = 'order' | 'shuffle' | 'repeat-one';

/** 解析 Navidrome JSON 格式歌词（纯函数，模块级，避免随组件重建） */
const parseLyrics = (lyricsText: string): Lyric[] => {
  try {
    const lyricsData: LyricData[] = JSON.parse(lyricsText);
    if (!lyricsData || lyricsData.length === 0) return [];

    const firstLyric = lyricsData[0];
    if (!firstLyric.line || firstLyric.line.length === 0) return [];

    // 转换时间格式（毫秒转秒）、过滤空歌词并按时间排序
    return firstLyric.line
      .filter(line => line.value.trim() !== '')
      .map(line => ({
        time: line.start / 1000,
        text: line.value.trim(),
      }))
      .sort((a, b) => a.time - b.time);
  } catch (error) {
    console.error('Error parsing lyrics:', error);
    return [];
  }
};

/** 二分查找：返回 time 所处歌词行索引（时间在首句之前返回 -1） */
const findLyricIndex = (list: Lyric[], time: number): number => {
  let lo = 0;
  let hi = list.length - 1;
  let ans = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (list[mid].time <= time) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
};

/** 序列化歌曲时剔除体积较大的内嵌歌词字段 */
const stripSong = (song: SongResponse): SongResponse => ({
  ...song,
  lyrics: undefined,
});

/** 持久化的播放状态结构 */
interface PersistedPlayerState {
  queue: SongResponse[];
  currentSong: SongResponse | null;
  playMode: PlayMode;
  currentTime: number;
}

export interface PlayerContextProps {
  currentSong: SongResponse | null;
  isPlaying: boolean;
  setCurrentSong: (song: SongResponse) => void;
  getSongStreamUrl: (songId: string) => string;
  togglePlay: () => void;
  playNext: () => void;
  playPrevious: () => void;
  queue: SongResponse[];
  addToQueue: (songs: SongResponse[]) => void;
  clearQueue: () => void;
  removeFromQueue: (songId: string) => void;
  progress: number;
  currentTime: number;
  setCurrentTime: (time: number) => void;
  seekTo: (position: number) => void;
  isPlayerReady: boolean;
  currentLyric: string;
  nextLyric: string;
  lyrics: Lyric[];
  getCurrentLyricIndex: (currentTime: number) => number;
  audioRef?: React.RefObject<HTMLAudioElement | null>;
  playMode: PlayMode;
  setPlayMode: (mode: PlayMode) => void;
}

export const PlayerContext = createContext<PlayerContextProps>({
  currentSong: null,
  isPlaying: false,
  setCurrentSong: () => {},
  getSongStreamUrl: () => '',
  togglePlay: () => {},
  playNext: () => {},
  playPrevious: () => {},
  queue: [],
  addToQueue: () => {},
  clearQueue: () => {},
  removeFromQueue: () => {},
  progress: 0,
  currentTime: 0,
  setCurrentTime: () => {},
  seekTo: () => {},
  isPlayerReady: false,
  currentLyric: '',
  nextLyric: '',
  lyrics: [],
  getCurrentLyricIndex: () => -1,
  audioRef: undefined,
  playMode: 'order',
  setPlayMode: () => {},
});

export const PlayerProvider = ({ children }: { children: ReactNode }) => {
  const [currentSong, setCurrentSongState] = useState<SongResponse | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [queue, setQueue] = useState<SongResponse[]>([]);
  const [isPlayerReady, setIsPlayerReady] = useState(false);
  const [progress, setProgress] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [currentLyric, setCurrentLyric] = useState('');
  const [nextLyric, setNextLyric] = useState('');
  const [lyrics, setLyrics] = useState<Lyric[]>([]);
  const [playMode, setPlayMode] = useState<PlayMode>('order');

  const { serverUrl, subsonicToken, subsonicSalt, username } = useAuth();
  const isInitialized = useRef(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const progressInterval = useRef<ReturnType<typeof setInterval> | null>(null);

  // auth 的 ref 镜像：让 URL 构建函数保持稳定引用，同时总能拿到最新值
  const authRef = useRef<SubsonicAuth>({ serverUrl, username, subsonicToken, subsonicSalt });
  useEffect(() => {
    authRef.current = { serverUrl, username, subsonicToken, subsonicSalt };
  });

  // 歌词的 ref 镜像：供进度轮询稳定读取
  const lyricsRef = useRef<Lyric[]>([]);
  useEffect(() => {
    lyricsRef.current = lyrics;
  }, [lyrics]);

  // 歌词文本缓存：轮询时跳过无变化的 setState，避免无效渲染
  const lastLyricPairRef = useRef({ current: '', next: '' });

  // 持久化恢复标记：恢复的队列/歌曲不自动播放，等用户点击继续
  const restoreRef = useRef(false);
  const restoreSeekRef = useRef(0);

  // Web 端挂载时创建 Audio 元素（须先于事件绑定 effect 执行）
  useEffect(() => {
    if (Platform.OS === 'web' && !audioRef.current) {
      audioRef.current = new Audio();
    }
  }, []);

  // 包装 setCurrentSong：设置新歌曲时自动开始播放，并按需加入队列
  const setCurrentSong = useCallback((song: SongResponse) => {
    setCurrentSongState(song);
    setIsPlaying(true);
    setQueue(prevQueue => {
      // 如果队列中已存在该歌曲，则不重复添加
      if (prevQueue.some(s => s.id === song.id)) return prevQueue;
      return [...prevQueue, song];
    });
  }, []);

  // 获取音频流 URL（稳定引用，内部读 authRef）
  const getSongStreamUrl = useCallback(
    (songId: string) => buildStreamUrl(authRef.current, songId),
    []
  );

  // 获取歌词
  const fetchLyrics = useCallback(async (songId: string): Promise<Lyric[]> => {
    const auth = authRef.current;
    if (!auth.serverUrl) return [];
    try {
      const response = await axios.get(`${auth.serverUrl}/rest/getLyrics`, {
        params: buildSubsonicParams(auth, { id: songId }),
      });
      const lyricEntry = response.data?.['subsonic-response']?.lyrics;
      if (lyricEntry) {
        return parseLyrics(lyricEntry.value);
      }
      return [];
    } catch (error) {
      console.error('Error fetching lyrics:', error);
      return [];
    }
  }, []);

  // 更新当前/下一句歌词（仅在文本变化时 setState）
  const updateCurrentLyric = useCallback((time: number) => {
    const list = lyricsRef.current;
    if (!list.length) {
      if (lastLyricPairRef.current.current !== '' || lastLyricPairRef.current.next !== '') {
        lastLyricPairRef.current = { current: '', next: '' };
        setCurrentLyric('');
        setNextLyric('');
      }
      return;
    }

    const idx = findLyricIndex(list, time);
    // 时间在第一句之前时显示空，等待首句到来
    const cur = idx >= 0 ? list[idx].text : '';
    const nxt = idx >= 0 && idx + 1 < list.length ? list[idx + 1].text : list[0]?.text ?? '';

    if (lastLyricPairRef.current.current === cur && lastLyricPairRef.current.next === nxt) return;
    lastLyricPairRef.current = { current: cur, next: nxt };
    setCurrentLyric(cur);
    setNextLyric(nxt);
  }, []);

  // 获取当前歌词索引（二分查找）
  const getCurrentLyricIndex = useCallback((time: number) => {
    const list = lyricsRef.current;
    if (!list || list.length === 0) return -1;
    return findLyricIndex(list, time);
  }, []);

  // 初始化播放器 + 注册播放状态监听
  useEffect(() => {
    const setupPlayer = async () => {
      if (isInitialized.current) return;
      try {
        if (Platform.OS !== 'web') {
          // 检查是否已初始化，防止多次 setup
          const state = await TrackPlayer.getState().catch(() => null);
          if (state !== null) {
            isInitialized.current = true;
            setIsPlayerReady(true);
            setIsPlaying(state === State.Playing);
            return;
          }
          await TrackPlayer.setupPlayer();
          TrackPlayer.updateOptions({
            capabilities: [
              Capability.Play,
              Capability.Pause,
              Capability.SkipToNext,
              Capability.SkipToPrevious,
              Capability.Stop,
            ],
          });
          setIsPlaying(true);
        }
        isInitialized.current = true;
        setIsPlayerReady(true);
        console.log('Player initialized successfully');
      } catch (error) {
        console.error('Error setting up player:', error);
        isInitialized.current = false;
        setIsPlayerReady(false);
      }
    };
    setupPlayer();

    let stateListener: { remove: () => void } | null = null;
    if (Platform.OS !== 'web') {
      // 监听原生 TrackPlayer 播放状态，保持 isPlaying 全局同步
      stateListener = TrackPlayer.addEventListener(Event.PlaybackState, (data) => {
        setIsPlaying(data.state === State.Playing);
      });
    }

    return () => {
      if (Platform.OS !== 'web') {
        if (stateListener && stateListener.remove) stateListener.remove();
        TrackPlayer.reset();
      }
      if (progressInterval.current) {
        clearInterval(progressInterval.current);
        progressInterval.current = null;
      }
    };
  }, []);

  // 播放下一首（依据播放模式）
  const playNext = useCallback(() => {
    if (!currentSong || queue.length === 0 || !isPlayerReady) return;
    try {
      const currentIndex = queue.findIndex(song => song.id === currentSong.id);
      if (playMode === 'shuffle') {
        // 随机播放，排除当前歌曲
        const otherSongs = queue.filter(song => song.id !== currentSong.id);
        if (otherSongs.length > 0) {
          const nextSong = otherSongs[Math.floor(Math.random() * otherSongs.length)];
          setCurrentSong(nextSong);
        }
      } else if (playMode === 'repeat-one') {
        // 单曲循环，重播当前歌曲
        if (Platform.OS === 'web' && audioRef.current) {
          audioRef.current.currentTime = 0;
          audioRef.current.play();
        } else {
          TrackPlayer.seekTo(0).then(() => TrackPlayer.play()).catch(err =>
            console.error('Error repeating current song:', err)
          );
        }
      } else {
        // 顺序播放，最后一首后回到队首
        if (currentIndex < queue.length - 1) {
          setCurrentSong(queue[currentIndex + 1]);
        } else if (queue.length > 0) {
          setCurrentSong(queue[0]);
        }
      }
    } catch (error) {
      console.error('Error playing next:', error);
    }
  }, [currentSong, queue, playMode, isPlayerReady, setCurrentSong]);

  // 播放上一首
  const playPrevious = useCallback(() => {
    if (!currentSong || queue.length === 0 || !isPlayerReady) return;
    try {
      const currentIndex = queue.findIndex(song => song.id === currentSong.id);
      if (playMode === 'shuffle') {
        const otherSongs = queue.filter(song => song.id !== currentSong.id);
        if (otherSongs.length > 0) {
          const prevSong = otherSongs[Math.floor(Math.random() * otherSongs.length)];
          setCurrentSong(prevSong);
        }
      } else if (playMode === 'repeat-one') {
        setCurrentSong(currentSong);
      } else {
        if (currentIndex > 0) {
          setCurrentSong(queue[currentIndex - 1]);
        }
      }
    } catch (error) {
      console.error('Error playing previous:', error);
    }
  }, [currentSong, queue, playMode, isPlayerReady, setCurrentSong]);

  // Web端 audio 播放状态监听，保持 isPlaying 全局同步（audio 元素已在挂载时创建）
  useEffect(() => {
    if (Platform.OS !== 'web' || !audioRef.current) return;
    const audio = audioRef.current;
    const onPlay = () => setIsPlaying(true);
    const onPause = () => setIsPlaying(false);
    const onEnded = () => {
      setIsPlaying(false);
      playNext(); // 播放结束时自动切歌
    };
    audio.addEventListener('play', onPlay);
    audio.addEventListener('pause', onPause);
    audio.addEventListener('ended', onEnded);
    return () => {
      audio.removeEventListener('play', onPlay);
      audio.removeEventListener('pause', onPause);
      audio.removeEventListener('ended', onEnded);
    };
  }, [playNext]);

  // 原生端 TrackPlayer 播放结束监听
  useEffect(() => {
    if (Platform.OS === 'web') return;
    const onQueueEnded = TrackPlayer.addEventListener(Event.PlaybackQueueEnded, () => {
      playNext();
    });
    return () => {
      if (onQueueEnded && onQueueEnded.remove) onQueueEnded.remove();
    };
  }, [playNext]);

  // 恢复持久化的播放状态（队列/播放模式/当前歌曲/进度）
  // 恢复的歌曲不自动播放，由用户点击继续；声明在 loadTrack effect 之前以保证先执行
  useEffect(() => {
    if (!isPlayerReady) return;
    const restore = async () => {
      try {
        const raw = await storageService.getItem(STORAGE_KEYS.PLAYER_STATE);
        if (!raw) return;
        const saved = JSON.parse(raw) as PersistedPlayerState;
        if (!Array.isArray(saved.queue) || saved.queue.length === 0) return;
        setQueue(saved.queue);
        if (saved.currentSong && saved.queue.some(song => song.id === saved.currentSong!.id)) {
          restoreRef.current = true;
          restoreSeekRef.current =
            typeof saved.currentTime === 'number' && saved.currentTime > 0 ? saved.currentTime : 0;
          setCurrentSongState(saved.currentSong);
        }
        if (saved.playMode) {
          setPlayMode(saved.playMode);
        }
      } catch (error) {
        console.error('Error restoring player state:', error);
      }
    };
    restore();
  }, [isPlayerReady]);

  // 监听歌曲变化：加载歌词 + 加载音轨
  useEffect(() => {
    const loadTrack = async () => {
      if (!currentSong || !isPlayerReady) return;
      setLyrics([]); // 切歌时立即清空歌词
      setCurrentLyric('');
      setNextLyric('');
      lastLyricPairRef.current = { current: '', next: '' };
      // 恢复场景：不自动播放，仅恢复历史进度（先读出并清除标记）
      const isRestore = restoreRef.current;
      const restoreSeek = restoreSeekRef.current;
      restoreRef.current = false;
      restoreSeekRef.current = 0;
      try {
        let parsedLyrics: Lyric[] = [];
        if (currentSong.lyrics) {
          parsedLyrics = parseLyrics(currentSong.lyrics);
        } else {
          parsedLyrics = await fetchLyrics(currentSong.id);
        }
        setLyrics(parsedLyrics);
        // 初始化时更新一次歌词
        if (Platform.OS === 'web' && audioRef.current) {
          updateCurrentLyric(audioRef.current.currentTime);
        } else if (Platform.OS !== 'web') {
          const position = await TrackPlayer.getPosition();
          updateCurrentLyric(position);
        }
        if (Platform.OS !== 'web') {
          await TrackPlayer.reset();
          await TrackPlayer.add({
            id: currentSong.id,
            url: getSongStreamUrl(currentSong.id),
            title: currentSong.title,
            artist: currentSong.artist,
            // 封面应指向图片端点（原先误用音频流地址导致通知栏封面无法显示）
            artwork: buildCoverArtUrl(authRef.current, currentSong.albumId),
          });
          if (isRestore) {
            // 恢复会话：不自动播放，仅恢复历史进度
            if (restoreSeek > 0) {
              await TrackPlayer.seekTo(restoreSeek);
            }
          } else {
            await TrackPlayer.play();
          }
        } else {
          // Web端播放
          if (!audioRef.current) {
            audioRef.current = new Audio();
          }
          const audio = audioRef.current;
          audio.src = getSongStreamUrl(currentSong.id);
          if (isRestore) {
            if (restoreSeek > 0) {
              // 等元数据加载完成后再恢复进度（设置 src 后立即赋值 currentTime 会被忽略）
              const onMeta = () => {
                if (audioRef.current) {
                  audioRef.current.currentTime = restoreSeek;
                }
                audio.removeEventListener('loadedmetadata', onMeta);
              };
              audio.addEventListener('loadedmetadata', onMeta);
            }
          } else {
            audio.play();
          }
        }
      } catch (error) {
        setLyrics([]);
        setCurrentLyric('');
        setNextLyric('');
        console.error('Error loading track:', error);
      }
    };
    loadTrack();
    // 故意不响应 URL 构建函数：仅在歌曲/播放器就绪时加载音轨
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentSong, isPlayerReady]);

  // 进度与歌词轮询：播放时 100ms，暂停时降为 500ms 减少无效开销
  useEffect(() => {
    if (!currentSong || !isPlayerReady) return;

    const updateProgress = async () => {
      try {
        if (Platform.OS === 'web') {
          if (audioRef.current) {
            const time = audioRef.current.currentTime;
            const duration = audioRef.current.duration;
            setCurrentTime(time);
            setProgress(duration > 0 ? time / duration : 0);
            updateCurrentLyric(time);
          }
        } else {
          const position = await TrackPlayer.getPosition();
          const duration = await TrackPlayer.getDuration();
          setCurrentTime(position);
          setProgress(duration > 0 ? position / duration : 0);
          updateCurrentLyric(position);
        }
      } catch (error) {
        console.error('Error updating progress:', error);
      }
    };

    progressInterval.current = setInterval(updateProgress, isPlaying ? 100 : 500);

    return () => {
      if (progressInterval.current) {
        clearInterval(progressInterval.current);
        progressInterval.current = null;
      }
    };
  }, [currentSong, isPlayerReady, isPlaying, updateCurrentLyric]);

  // 播放控制
  const togglePlay = useCallback(async () => {
    if (!currentSong || !isPlayerReady) return;
    try {
      if (Platform.OS !== 'web') {
        const state = await TrackPlayer.getState();
        if (state === State.Playing) {
          await TrackPlayer.pause();
        } else {
          await TrackPlayer.play();
        }
      } else {
        if (!audioRef.current) return;
        if (audioRef.current.paused) {
          audioRef.current.play();
        } else {
          audioRef.current.pause();
        }
      }
    } catch (error) {
      console.error('Error toggling play:', error);
    }
  }, [currentSong, isPlayerReady]);

  // 移除队列中的歌曲；若移除的是当前歌曲则自动切换到相邻歌曲
  const removeFromQueue = useCallback((songId: string) => {
    setQueue(prevQueue => {
      const idx = prevQueue.findIndex(song => song.id === songId);
      if (idx === -1) return prevQueue;
      const nextQueue = prevQueue.filter(song => song.id !== songId);
      setCurrentSongState(prev => {
        if (!prev || prev.id !== songId) return prev;
        if (nextQueue.length === 0) return null;
        return nextQueue[Math.min(idx, nextQueue.length - 1)];
      });
      return nextQueue;
    });
  }, []);

  // 添加到播放队列
  const addToQueue = useCallback((songs: SongResponse[]) => {
    setQueue(prevQueue => [...prevQueue, ...songs]);
  }, []);

  // 清空播放队列
  const clearQueue = useCallback(() => setQueue([]), []);

  // 跳转到指定位置
  const seekTo = useCallback(async (position: number) => {
    if (!currentSong || !isPlayerReady) return;
    try {
      if (Platform.OS !== 'web') {
        await TrackPlayer.seekTo(position);
      } else {
        if (audioRef.current) {
          audioRef.current.currentTime = position;
        }
      }
    } catch (error) {
      console.error('Error seeking:', error);
    }
  }, [currentSong, isPlayerReady]);

  // 持久化播放状态（debounce 500ms：进度高频变化时只在静止后写入）
  useEffect(() => {
    const timer = setTimeout(() => {
      const payload: PersistedPlayerState = {
        queue: queue.slice(0, 100).map(stripSong),
        currentSong: currentSong ? stripSong(currentSong) : null,
        playMode,
        currentTime,
      };
      storageService
        .setItem(STORAGE_KEYS.PLAYER_STATE, JSON.stringify(payload))
        .catch(error => console.error('Error persisting player state:', error));
    }, 500);
    return () => clearTimeout(timer);
  }, [queue, currentSong, playMode, currentTime]);

  return (
    <PlayerContext.Provider
      value={{
        currentSong,
        isPlaying,
        setCurrentSong,
        getSongStreamUrl,
        togglePlay,
        playNext,
        playPrevious,
        queue,
        addToQueue,
        clearQueue,
        removeFromQueue,
        progress,
        currentTime,
        setCurrentTime,
        seekTo,
        isPlayerReady,
        currentLyric,
        nextLyric,
        lyrics,
        getCurrentLyricIndex,
        audioRef,
        playMode,
        setPlayMode,
      }}
    >
      {children}
    </PlayerContext.Provider>
  );
};

export const usePlayer = () => {
  const context = useContext(PlayerContext);
  if (!context) {
    throw new Error('usePlayer must be used within a PlayerProvider');
  }
  return context;
};
