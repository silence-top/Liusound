import AsyncStorage from '@react-native-async-storage/async-storage';
import * as SecureStore from 'expo-secure-store';

/** 全局统一的存储键（所有模块共用，避免重复定义） */
export const STORAGE_KEYS = {
  TOKEN: 'token',
  USERNAME: 'username',
  SUBSONIC_TOKEN: 'subsonicToken',
  SUBSONIC_SALT: 'subsonicSalt',
  SERVER_URL: 'server_url',
  PLAYER_STATE: 'player_state',
} as const;

/** 兼容别名：历史代码通过 CONFIG_KEYS.SERVER_URL 访问 */
export const CONFIG_KEYS = STORAGE_KEYS;

/** 需要加密安全存储的敏感键（SecureStore 键名仅允许字母/数字/./-/_，以上均合规） */
const SECURE_KEYS: ReadonlySet<string> = new Set([
  STORAGE_KEYS.TOKEN,
  STORAGE_KEYS.SUBSONIC_TOKEN,
  STORAGE_KEYS.SUBSONIC_SALT,
]);

/**
 * 统一存储服务：
 * - 敏感键（token / subsonicToken / subsonicSalt）走 SecureStore（iOS Keychain / Android Keystore）
 * - 其余键走 AsyncStorage
 * - SecureStore 不可用时自动降级 AsyncStorage；读取时自动迁移历史明文数据
 */
export const storageService = {
  async getItem(key: string): Promise<string | null> {
    if (!SECURE_KEYS.has(key)) {
      return AsyncStorage.getItem(key);
    }
    try {
      const value = await SecureStore.getItemAsync(key);
      if (value !== null) return value;
      // 兼容迁移：旧版本的明文数据从 AsyncStorage 迁入 SecureStore
      const legacy = await AsyncStorage.getItem(key);
      if (legacy !== null) {
        await SecureStore.setItemAsync(key, legacy);
        await AsyncStorage.removeItem(key);
      }
      return legacy;
    } catch (error) {
      console.warn(`SecureStore unavailable for "${key}", fallback to AsyncStorage`, error);
      return AsyncStorage.getItem(key);
    }
  },

  async setItem(key: string, value: string): Promise<void> {
    if (!SECURE_KEYS.has(key)) {
      return AsyncStorage.setItem(key, value);
    }
    try {
      await SecureStore.setItemAsync(key, value);
      // 清理可能残留的历史明文
      await AsyncStorage.removeItem(key).catch(() => undefined);
    } catch (error) {
      console.warn(`SecureStore unavailable for "${key}", fallback to AsyncStorage`, error);
      await AsyncStorage.setItem(key, value);
    }
  },

  async removeItem(key: string): Promise<void> {
    const tasks: Promise<void>[] = [AsyncStorage.removeItem(key)];
    if (SECURE_KEYS.has(key)) {
      tasks.push(SecureStore.deleteItemAsync(key));
    }
    // 两边都尽力清理，单个失败不影响另一个
    await Promise.all(tasks.map(task => task.catch(() => undefined)));
  },

  async multiRemove(keys: string[]): Promise<void> {
    await Promise.all(keys.map(key => this.removeItem(key)));
  },
};

export const configService = {
  getServerUrl: async () => {
    return await AsyncStorage.getItem(CONFIG_KEYS.SERVER_URL);
  },

  setServerUrl: async (url: string) => {
    await AsyncStorage.setItem(CONFIG_KEYS.SERVER_URL, url);
  },
};

export default configService;
