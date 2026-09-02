import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  Switch,
  Alert,
  ActivityIndicator,
} from 'react-native';
import { useRoute } from '@react-navigation/native';
import { useAuth } from '../contexts/AuthContext';
import { configService } from '../services/config';
import axios from 'axios';

const LoginScreen = () => {
  const route = useRoute();
  const { serverName } = route.params as { serverName: string };
  const { login } = useAuth();

  const [serverUrl, setServerUrl] = useState('http://');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [directMode, setDirectMode] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    // 加载保存的服务器地址
    const loadServerUrl = async () => {
      try {
        const savedUrl = await configService.getServerUrl();
        if (savedUrl) {
          setServerUrl(savedUrl);
        }
      } catch (error) {
        console.error('Failed to load server URL:', error);
      }
    };
    loadServerUrl();
  }, []);

  const validateInputs = () => {
    if (!serverUrl || serverUrl === 'http://') {
      Alert.alert('错误', '请输入服务器地址');
      return false;
    }
    if (!username) {
      Alert.alert('错误', '请输入用户名');
      return false;
    }
    if (!password) {
      Alert.alert('错误', '请输入密码');
      return false;
    }
    return true;
  };

  const handleLogin = async () => {
    if (!validateInputs()) {
      return;
    }

    setIsLoading(true);
    try {
      // 规范化 URL
      let normalizedUrl = serverUrl.trim();
      if (!normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://')) {
        normalizedUrl = `http://${normalizedUrl}`;
      }
      // 移除末尾的斜杠
      normalizedUrl = normalizedUrl.replace(/\/$/, '');

      // 保存服务器地址
      await configService.setServerUrl(normalizedUrl);

      // 登录
      const response = await axios.post(`${normalizedUrl}/auth/login`, {
        username,
        password,
      });

      const { token, subsonicToken, subsonicSalt } = response.data;
      
      if (!token || !subsonicToken || !subsonicSalt) {
        throw new Error('登录响应缺少必要的认证信息');
      }

      // 使用新的 login 函数保存所有认证信息
      await login(username, token, subsonicToken, subsonicSalt, normalizedUrl);
    } catch (error) {
      Alert.alert('登录失败', error instanceof Error ? error.message : '未知错误');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.serverName}>{serverName}</Text>
      </View>

      <View style={styles.formContainer}>
        <View style={styles.inputContainer}>
          <Text style={styles.label}>主机地址</Text>
          <TextInput
            style={styles.input}
            value={serverUrl}
            onChangeText={setServerUrl}
            placeholder="http://"
            placeholderTextColor="#666"
            autoCapitalize="none"
            keyboardType="url"
          />
        </View>

        <View style={styles.inputContainer}>
          <Text style={styles.label}>用户名</Text>
          <TextInput
            style={styles.input}
            value={username}
            onChangeText={setUsername}
            placeholder="请输入用户名"
            placeholderTextColor="#666"
            autoCapitalize="none"
          />
        </View>

        <View style={styles.inputContainer}>
          <Text style={styles.label}>密码</Text>
          <TextInput
            style={styles.input}
            value={password}
            onChangeText={setPassword}
            placeholder="请输入密码"
            placeholderTextColor="#666"
            secureTextEntry
          />
        </View>

        <View style={styles.switchContainer}>
          <Text style={styles.switchLabel}>直连模式</Text>
          <Switch
            value={directMode}
            onValueChange={setDirectMode}
            trackColor={{ false: '#767577', true: '#4CAF50' }}
            thumbColor={directMode ? '#fff' : '#f4f3f4'}
          />
        </View>

        <TouchableOpacity 
          style={[styles.loginButton, isLoading && styles.loginButtonDisabled]}
          onPress={handleLogin}
          disabled={isLoading}
        >
          {isLoading ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.loginButtonText}>登录</Text>
          )}
        </TouchableOpacity>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 20,
    backgroundColor: '#001B2E',
  },
  header: {
    alignItems: 'center',
    marginTop: 40,
    marginBottom: 40,
  },
  serverName: {
    color: '#fff',
    fontSize: 24,
    fontWeight: 'bold',
  },
  formContainer: {
    flex: 1,
  },
  inputContainer: {
    marginBottom: 20,
  },
  label: {
    color: '#fff',
    marginBottom: 8,
    fontSize: 16,
  },
  input: {
    backgroundColor: '#1a2c3a',
    borderRadius: 8,
    padding: 12,
    color: '#fff',
    fontSize: 16,
  },
  switchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 30,
  },
  switchLabel: {
    color: '#fff',
    fontSize: 16,
  },
  loginButton: {
    backgroundColor: '#2196F3',
    borderRadius: 8,
    padding: 15,
    alignItems: 'center',
  },
  loginButtonDisabled: {
    backgroundColor: '#1565C0',
    opacity: 0.7,
  },
  loginButtonText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: 'bold',
  },
});

export default LoginScreen; 