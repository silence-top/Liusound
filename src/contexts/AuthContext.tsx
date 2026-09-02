import React, { createContext, useContext, useState, useEffect } from 'react';
import { setAuthCache, clearAuthCache } from '../services/navidromeApi';
import { STORAGE_KEYS, storageService } from '../services/config';

interface AuthContextType {
  isAuthenticated: boolean;
  isLoading: boolean;
  username: string;
  token: string;
  subsonicToken: string;
  subsonicSalt: string;
  serverUrl: string;
  login: (username: string, token: string, subsonicToken: string, subsonicSalt: string, serverUrl: string) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [username, setUsername] = useState('');
  const [token, setToken] = useState('');
  const [subsonicToken, setSubsonicToken] = useState('');
  const [subsonicSalt, setSubsonicSalt] = useState('');
  const [serverUrl, setServerUrl] = useState('');

  useEffect(() => {
    const loadAuthState = async () => {
      try {
        const [savedUsername, savedToken, savedSubsonicToken, savedSubsonicSalt, savedServerUrl] = await Promise.all([
          storageService.getItem(STORAGE_KEYS.USERNAME),
          storageService.getItem(STORAGE_KEYS.TOKEN),
          storageService.getItem(STORAGE_KEYS.SUBSONIC_TOKEN),
          storageService.getItem(STORAGE_KEYS.SUBSONIC_SALT),
          storageService.getItem(STORAGE_KEYS.SERVER_URL),
        ]);

        if (savedUsername && savedToken && savedSubsonicToken && savedSubsonicSalt && savedServerUrl) {
          setUsername(savedUsername);
          setToken(savedToken);
          setSubsonicToken(savedSubsonicToken);
          setSubsonicSalt(savedSubsonicSalt);
          setServerUrl(savedServerUrl);
          setIsAuthenticated(true);
        }
      } catch (error) {
        console.error('Error loading auth state:', error);
      } finally {
        setIsLoading(false);
      }
    };

    loadAuthState();
  }, []);

  const login = async (newUsername: string, newToken: string, newSubsonicToken: string, newSubsonicSalt: string, newServerUrl: string) => {
    try {
      await Promise.all([
        storageService.setItem(STORAGE_KEYS.USERNAME, newUsername),
        storageService.setItem(STORAGE_KEYS.TOKEN, newToken),
        storageService.setItem(STORAGE_KEYS.SUBSONIC_TOKEN, newSubsonicToken),
        storageService.setItem(STORAGE_KEYS.SUBSONIC_SALT, newSubsonicSalt),
        storageService.setItem(STORAGE_KEYS.SERVER_URL, newServerUrl),
      ]);
      // 同步更新 navidromeApi 的内存缓存，使拦截器立即可用新凭证
      setAuthCache(newServerUrl, newToken);
      setUsername(newUsername);
      setToken(newToken);
      setSubsonicToken(newSubsonicToken);
      setSubsonicSalt(newSubsonicSalt);
      setServerUrl(newServerUrl);
      setIsAuthenticated(true);
    } catch (error) {
      console.error('Error saving auth state:', error);
      throw error;
    }
  };

  const logout = async () => {
    try {
      await storageService.multiRemove([
        STORAGE_KEYS.USERNAME,
        STORAGE_KEYS.TOKEN,
        STORAGE_KEYS.SUBSONIC_TOKEN,
        STORAGE_KEYS.SUBSONIC_SALT,
        STORAGE_KEYS.SERVER_URL,
        // 播放队列属于服务器会话，登出时一并清除，避免下次登录恢复到旧服务器的歌曲
        STORAGE_KEYS.PLAYER_STATE,
      ]);
      // 同步清理 navidromeApi 的内存缓存
      clearAuthCache();
      setUsername('');
      setToken('');
      setSubsonicToken('');
      setSubsonicSalt('');
      setServerUrl('');
      setIsAuthenticated(false);
    } catch (error) {
      console.error('Error clearing auth state:', error);
      throw error;
    }
  };

  return (
    <AuthContext.Provider
      value={{
        isAuthenticated,
        isLoading,
        username,
        token,
        subsonicToken,
        subsonicSalt,
        serverUrl,
        login,
        logout,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export default AuthProvider; 