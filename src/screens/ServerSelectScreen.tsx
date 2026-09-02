import React from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Image,
  ScrollView,
  SafeAreaView,
} from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { NavigationProp } from '../types/navigation';

const servers = [
  {
    id: 'navidrome',
    name: 'Navidrome',
    icon: require('../assets/navidrome.png'),
  },
];

const ServerSelectScreen = () => {
  const navigation = useNavigation<NavigationProp>();

  const handleServerSelect = (serverId: string, serverName: string) => {
    navigation.navigate('Login', {
      serverId,
      serverName,
    });
  };

  return (
    <SafeAreaView style={styles.safeArea}>
      <View style={styles.header}>
        <Image
          source={require('../assets/logo.png')}
          style={styles.logo}
        />
        <Text style={styles.title}>选择音乐服务</Text>
      </View>

      <ScrollView style={styles.container}>
        <View style={styles.content}>
          {servers.map(server => (
            <TouchableOpacity
              key={server.id}
              style={styles.serverItem}
              onPress={() => handleServerSelect(server.id, server.name)}
            >
              <Image source={server.icon} style={styles.serverIcon} />
              <Text style={styles.serverName}>{server.name}</Text>
              <Text style={styles.arrow}>›</Text>
            </TouchableOpacity>
          ))}

          <TouchableOpacity style={styles.qrButton}>
            <Text style={styles.qrText}>扫描二维码添加</Text>
            <Text style={styles.arrow}>›</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: '#001B2E',
  },
  header: {
    alignItems: 'center',
    paddingVertical: 20,
  },
  logo: {
    width: 60,
    height: 60,
    marginBottom: 10,
  },
  title: {
    color: '#fff',
    fontSize: 20,
    fontWeight: 'bold',
  },
  container: {
    flex: 1,
  },
  content: {
    padding: 16,
  },
  serverItem: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1a2c3a',
    borderRadius: 8,
    padding: 16,
    marginBottom: 12,
  },
  serverIcon: {
    width: 28,
    height: 28,
    marginRight: 12,
    borderRadius: 6,
  },
  serverName: {
    flex: 1,
    color: '#fff',
    fontSize: 16,
  },
  arrow: {
    color: '#666',
    fontSize: 24,
  },
  qrButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1a2c3a',
    borderRadius: 8,
    padding: 16,
    marginTop: 20,
  },
  qrText: {
    flex: 1,
    color: '#fff',
    fontSize: 16,
  },
});

export default ServerSelectScreen; 