import React, { useEffect, useRef, useState, useCallback } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Platform, Animated } from 'react-native';
import Svg, { Circle } from 'react-native-svg';
import Icon from 'react-native-vector-icons/MaterialIcons';
import { usePlayer } from '../contexts/PlayerContext';
import { useAuth } from '../contexts/AuthContext';
import { buildCoverArtUrl } from '../utils/subsonic';
import FullScreenPlayer from './FullScreenPlayer';
import QueueModal from './QueueModal';

const CIRCLE_SIZE = 48; // 圆的直径
const STROKE_WIDTH = 2; // 圆环宽度
const RADIUS = (CIRCLE_SIZE - STROKE_WIDTH) / 2; // 圆的半径
const CIRCLE_LENGTH = 2 * Math.PI * RADIUS; // 圆的周长

const MiniPlayer: React.FC = () => {
  const { 
    currentSong, 
    isPlaying, 
    togglePlay, 
    progress = 0, 
    currentLyric, 
    nextLyric,
  } = usePlayer();
  const { username, subsonicToken, subsonicSalt, serverUrl } = useAuth();
  const [rotation] = useState(new Animated.Value(0));
  const [isPlayerVisible, setIsPlayerVisible] = useState(false);
  const [showQueueModal, setShowQueueModal] = useState(false);
  const rotationAnimation = useRef<Animated.CompositeAnimation | null>(null);

  // Optimized rotation animation
  useEffect(() => {
    if (isPlaying) {
      rotationAnimation.current = Animated.loop(
        Animated.timing(rotation, {
          toValue: 1,
          duration: 10000,
          useNativeDriver: true,
        })
      );
      rotationAnimation.current.start();
    } else {
      rotationAnimation.current?.stop();
      rotation.setValue(0);
    }

    return () => {
      rotationAnimation.current?.stop();
    };
  }, [isPlaying, rotation]);

  // 封面地址（复用共享 Subsonic 工具）
  const getCoverArtUrl = useCallback(
    (id: string) =>
      buildCoverArtUrl({ serverUrl, username, subsonicToken, subsonicSalt }, id),
    [serverUrl, username, subsonicToken, subsonicSalt]
  );

  // Memoized subtitle text
  const subtitleText = React.useMemo(() => {
    if (!currentSong) return '';
    
    // 如果有歌词，优先显示歌词
    if (currentLyric) return currentLyric;
    if (nextLyric) return nextLyric;
    
    // 没有歌词时显示歌手和专辑信息
    return `${currentSong.artist} - ${currentSong.album}`;
  }, [currentLyric, nextLyric, currentSong]);

  if (!currentSong) return null;

  const spin = rotation.interpolate({
    inputRange: [0, 1],
    outputRange: ['0deg', '360deg']
  });

  return (
    <>
      <View style={styles.container}>
        <TouchableOpacity 
          style={styles.coverContainer}
          onPress={togglePlay}
          activeOpacity={0.7}
        >
          <Animated.Image 
            source={{ uri: getCoverArtUrl(currentSong.albumId) }} 
            style={[
              styles.cover, 
              { transform: [{ rotate: spin }], zIndex: 1 }
            ]} 
          />
          {!isPlaying && (
            <View style={styles.playOverlay}>
              <Icon name="play-circle-filled" size={38} color="#fff" />
            </View>
          )}
          <Svg width={CIRCLE_SIZE} height={CIRCLE_SIZE} style={styles.progressCircle}> 
            <Circle
              cx={CIRCLE_SIZE / 2}
              cy={CIRCLE_SIZE / 2}
              r={RADIUS}
              stroke="rgba(255,255,255,0.2)"
              strokeWidth={STROKE_WIDTH}
              fill="transparent"
            />
            <Circle
              cx={CIRCLE_SIZE / 2}
              cy={CIRCLE_SIZE / 2}
              r={RADIUS}
              stroke="#1DB954"
              strokeWidth={STROKE_WIDTH}
              fill="transparent"
              strokeDasharray={CIRCLE_LENGTH}
              strokeDashoffset={CIRCLE_LENGTH * (1 - Math.max(0, progress))}
              strokeLinecap="round"
            />
          </Svg>
        </TouchableOpacity>
        <TouchableOpacity 
          style={styles.info} 
          onPress={() => setIsPlayerVisible(true)} 
          activeOpacity={0.7}
        >
          <Text style={styles.title} numberOfLines={1}>{currentSong.title}</Text>
          <Text style={styles.sub} numberOfLines={1}>{subtitleText}</Text>
        </TouchableOpacity>
        <TouchableOpacity 
          style={styles.playButton} 
          onPress={() => setShowQueueModal(true)}
        >
          <Icon name="queue-music" size={28} color="#fff" />
        </TouchableOpacity>
      </View>

      <FullScreenPlayer 
        visible={isPlayerVisible}
        onClose={() => setIsPlayerVisible(false)}
      />

      <QueueModal visible={showQueueModal} onClose={() => setShowQueueModal(false)} />
    </>
  );
};

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#555B62',
    borderRadius: 28,
    marginHorizontal: 12,
    marginBottom: 16,
    paddingVertical: 8,
    paddingLeft: 8,
    paddingRight: 16,
    ...Platform.select({
      ios: {
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 2 },
        shadowOpacity: 0.15,
        shadowRadius: 8,
      },
      android: {
        elevation: 8,
      },
      web: {
        boxShadow: '0 2px 8px rgba(0, 0, 0, 0.15)',
      },
    }),
  },
  coverContainer: {
    width: CIRCLE_SIZE,
    height: CIRCLE_SIZE,
    marginRight: 12,
    position: 'relative',
    justifyContent: 'center',
    alignItems: 'center',
  },
  cover: {
    width: CIRCLE_SIZE - (STROKE_WIDTH * 2),
    height: CIRCLE_SIZE - (STROKE_WIDTH * 2),
    borderRadius: (CIRCLE_SIZE - (STROKE_WIDTH * 2)) / 2,
    backgroundColor: '#222',
  },
  playOverlay: {
    position: 'absolute',
    left: 0,
    top: 0,
    width: CIRCLE_SIZE,
    height: CIRCLE_SIZE,
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 2,
    backgroundColor: 'rgba(0,0,0,0.08)',
    borderRadius: CIRCLE_SIZE / 2,
  },
  progressCircle: {
    position: 'absolute',
    width: '100%',
    height: '100%',
    zIndex: 1,
    transform: [{ rotate: '-90deg' }],
  },
  info: {
    flex: 1,
    justifyContent: 'center',
  },
  title: {
    color: '#fff',
    fontSize: 17,
    fontWeight: 'bold',
  },
  sub: {
    color: '#e0e0e0',
    fontSize: 14,
    marginTop: 2,
    opacity: 0.8,
  },
  playButton: {
    marginLeft: 12,
    padding: 4,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.2)',
  },
});

export default MiniPlayer;
