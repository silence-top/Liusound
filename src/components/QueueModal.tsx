import React, { useRef } from 'react';
import { Modal, View, Text, TouchableOpacity, FlatList, StyleSheet, Platform, PanResponder, Animated } from 'react-native';
import Icon from 'react-native-vector-icons/MaterialIcons';
import { usePlayer } from '../contexts/PlayerContext';

interface QueueModalProps {
  visible: boolean;
  onClose: () => void;
}

const playModeTextMap = {
  order: '顺序播放',
  shuffle: '随机播放',
  'repeat-one': '单曲循环',
};

const playModeIconMap = {
  order: 'repeat',
  shuffle: 'shuffle',
  'repeat-one': 'repeat-one',
};

const DRAG_CLOSE_THRESHOLD = 60;

const QueueModal: React.FC<QueueModalProps> = ({ visible, onClose }) => {
  const {
    queue,
    currentSong,
    setCurrentSong,
    removeFromQueue,
    playMode,
    setPlayMode,
  } = usePlayer();

  // 拖拽动画
  const translateY = useRef(new Animated.Value(0)).current;
  const panResponder = useRef(
    PanResponder.create({
      onMoveShouldSetPanResponder: (_, gestureState) => Math.abs(gestureState.dy) > 8,
      onPanResponderMove: (_, gestureState) => {
        if (gestureState.dy > 0) {
          translateY.setValue(gestureState.dy);
        }
      },
      onPanResponderRelease: (_, gestureState) => {
        if (gestureState.dy > DRAG_CLOSE_THRESHOLD) {
          Animated.timing(translateY, {
            toValue: 500,
            duration: 180,
            useNativeDriver: true,
          }).start(() => {
            translateY.setValue(0);
            onClose();
          });
        } else {
          Animated.spring(translateY, {
            toValue: 0,
            useNativeDriver: true,
          }).start();
        }
      },
    })
  ).current;

  const handleSwitchMode = () => {
    if (playMode === 'order') setPlayMode('shuffle');
    else if (playMode === 'shuffle') setPlayMode('repeat-one');
    else setPlayMode('order');
  };

  return (
    <Modal
      visible={visible}
      transparent
      animationType="slide"
      onRequestClose={onClose}
    >
      <TouchableOpacity style={styles.overlay} activeOpacity={1} onPress={onClose} />
      <Animated.View
        style={[styles.container, { transform: [{ translateY }] }]}
        {...panResponder.panHandlers}
      >
        {/* 顶部小白条 */}
        <View style={styles.dragBarContainer}>
          <View style={styles.dragBar} />
        </View>
        <View style={styles.header}>
          <Text style={styles.title}>播放列表({queue.length})</Text>
          <TouchableOpacity style={styles.modeBtn} onPress={handleSwitchMode}>
            <Icon name={playModeIconMap[playMode]} size={22} color="#fff" />
            <Text style={styles.modeText}>{playModeTextMap[playMode]}</Text>
          </TouchableOpacity>
        </View>
        <FlatList
          data={queue}
          keyExtractor={item => item.id}
          renderItem={({ item }) => (
            <View style={[styles.item, currentSong?.id === item.id && styles.activeItem]}>
              <TouchableOpacity style={styles.itemInfo} onPress={() => setCurrentSong(item)}>
                <Text style={[styles.songTitle, currentSong?.id === item.id && styles.activeTitle]} numberOfLines={1}>{item.title}</Text>
                <Text style={styles.songSub} numberOfLines={1}>{item.artist}</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.deleteBtn} onPress={() => removeFromQueue(item.id)}>
                <Icon name="close" size={22} color="#fff" />
              </TouchableOpacity>
            </View>
          )}
          style={styles.list}
        />
      </Animated.View>
    </Modal>
  );
};

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.35)',
  },
  container: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: '#23272e',
    borderTopLeftRadius: 18,
    borderTopRightRadius: 18,
    paddingTop: 0,
    paddingBottom: Platform.OS === 'ios' ? 32 : 16,
    minHeight: 320,
    maxHeight: '70%',
  },
  dragBarContainer: {
    alignItems: 'center',
    paddingTop: 10,
    paddingBottom: 2,
  },
  dragBar: {
    width: 40,
    height: 4,
    borderRadius: 2,
    backgroundColor: 'rgba(255,255,255,0.35)',
    marginBottom: 4,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 18,
    marginBottom: 8,
  },
  title: {
    color: '#fff',
    fontSize: 17,
    fontWeight: 'bold',
  },
  modeBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 8,
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  modeText: {
    color: '#fff',
    fontSize: 14,
    marginLeft: 6,
  },
  list: {
    flexGrow: 0,
    marginBottom: 8,
    maxHeight: 320,
  },
  item: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 18,
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#333',
  },
  activeItem: {
    backgroundColor: 'rgba(30,180,255,0.08)',
  },
  itemInfo: {
    flex: 1,
    marginRight: 8,
  },
  songTitle: {
    color: '#fff',
    fontSize: 15,
  },
  activeTitle: {
    color: '#1DB954',
    fontWeight: 'bold',
  },
  songSub: {
    color: '#aaa',
    fontSize: 13,
    marginTop: 2,
  },
  deleteBtn: {
    padding: 4,
  },
});

export default QueueModal; 