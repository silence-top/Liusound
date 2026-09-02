import axios, { InternalAxiosRequestConfig, AxiosResponse, AxiosError } from 'axios';
import {
  SongResponse,
  PlaylistResponse,
  AlbumResponse,
  ArtistResponse,
  SearchResponse,
  SystemStatusResponse,
  LoginResponse,
} from '../types/api';
import { STORAGE_KEYS, storageService } from './config';

/**
 * 认证信息内存缓存
 * 避免在每个请求拦截器里读取 AsyncStorage（原先每次请求要 await 2 次）
 * 由 AuthContext 在 login/logout 时调用 setAuthCache/clearAuthCache 同步更新
 */
const authCache = {
  serverUrl: '',
  token: '',
};

export const setAuthCache = (serverUrl: string, token: string) => {
  authCache.serverUrl = serverUrl;
  authCache.token = token;
  api.defaults.baseURL = serverUrl || undefined;
};

export const clearAuthCache = () => {
  authCache.serverUrl = '';
  authCache.token = '';
  api.defaults.baseURL = undefined;
};

// 应用启动时从持久化存储恢复缓存（仅一次）
const initializeAuthCache = async () => {
  try {
    const [serverUrl, token] = await Promise.all([
      storageService.getItem(STORAGE_KEYS.SERVER_URL),
      storageService.getItem(STORAGE_KEYS.TOKEN),
    ]);
    setAuthCache(serverUrl || '', token || '');
  } catch (error) {
    console.error('Error initializing auth cache:', error);
  }
};
initializeAuthCache();

/** 通用查询参数类型（替换原先的 any） */
type QueryParams = Record<string, string | number | boolean | undefined>;

// 创建 axios 实例
const api = axios.create({
  timeout: 10000,
});

// 请求拦截器：直接读内存缓存，零 IO 开销
api.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    if (authCache.serverUrl) {
      config.baseURL = authCache.serverUrl;
    }
    if (authCache.token && config.headers) {
      config.headers.Authorization = `Bearer ${authCache.token}`;
      config.headers['x-nd-authorization'] = `Bearer ${authCache.token}`;
    }
    return config;
  },
  (error: AxiosError) => {
    return Promise.reject(error);
  }
);

// 响应拦截器
api.interceptors.response.use(
  (response: AxiosResponse) => {
    return response;
  },
  (error: AxiosError) => {
    if (error.response?.status === 401) {
      storageService.removeItem(STORAGE_KEYS.TOKEN);
    }
    return Promise.reject(error);
  }
);

// 认证相关 API
export const authApi = {
  login: async (username: string, password: string) => {
    const response = await api.post<LoginResponse>('/auth/login', { username, password });
    if (response.data.token) {
      await storageService.setItem(STORAGE_KEYS.TOKEN, response.data.token);
      setAuthCache(authCache.serverUrl, response.data.token);
    }
    return response;
  },
  logout: async () => {
    await api.post('/auth/logout');
    await storageService.removeItem(STORAGE_KEYS.TOKEN);
    clearAuthCache();
  },
};

// 用户相关 API
export const userApi = {
  getCurrentUser: () => api.get('/user/current'),
};

/** 服务端资源直链（基于内存缓存的 serverUrl，同步返回） */
const buildServerUrl = (path: string): string => `${authCache.serverUrl}${path}`;

// 专辑相关 API
export const albumApi = {
  getAlbums: (params?: QueryParams) => api.get<AlbumResponse[]>('/api/album', { params }),
  getAlbum: (id: string) => api.get<AlbumResponse>(`/api/album/${id}`),
  getAlbumSongs: (id: string) => api.get<SongResponse[]>(`/api/album/${id}/songs`),
  getAlbumArt: (id: string) => buildServerUrl(`/api/album/${id}/art`),
};

// 艺术家相关 API
export const artistApi = {
  getArtists: (params?: QueryParams) => api.get<ArtistResponse[]>('/api/artist', { params }),
  getArtist: (id: string) => api.get<ArtistResponse>(`/api/artist/${id}`),
  getArtistAlbums: (id: string) => api.get<AlbumResponse[]>(`/api/artist/${id}/albums`),
  getArtistSongs: (id: string) => api.get<SongResponse[]>(`/api/artist/${id}/songs`),
  getArtistImage: (id: string) => buildServerUrl(`/api/artist/${id}/image`),
};

// 歌曲相关 API
export const songApi = {
  getSongs: (params?: QueryParams) => api.get<SongResponse[]>('/api/song', { params }),
  getSong: (id: string) => api.get<SongResponse>(`/api/song/${id}`),
  getSongStream: (id: string) => buildServerUrl(`/api/song/${id}/stream`),
  getSimilarSongs: (params: QueryParams) => api.get(`/rest/getSimilarSongs`, { params }),
  getSongArt: (id: string) => buildServerUrl(`/api/song/${id}/art`),
};

// 播放列表相关 API
export const playlistApi = {
  getPlaylists: () => api.get<PlaylistResponse[]>('/playlist'),
  getPlaylist: (id: string) => api.get<PlaylistResponse>(`/playlist/${id}`),
  createPlaylist: (data: Partial<PlaylistResponse>) => api.post('/playlist', data),
  updatePlaylist: (id: string, data: Partial<PlaylistResponse>) => api.put(`/playlist/${id}`, data),
  deletePlaylist: (id: string) => api.delete(`/playlist/${id}`),
  addSongToPlaylist: (playlistId: string, songId: string) =>
    api.post(`/playlist/${playlistId}/songs`, { songId }),
  removeSongFromPlaylist: (playlistId: string, songId: string) =>
    api.delete(`/playlist/${playlistId}/songs/${songId}`),
};

// 搜索相关 API
export const searchApi = {
  search: (query: string, params?: QueryParams) =>
    api.get<SearchResponse>('/search', { params: { q: query, ...params } }),
};

// 系统相关 API
export const systemApi = {
  getStatus: () => api.get<SystemStatusResponse>('/system/status'),
  getVersion: () => api.get('/system/version'),
};

export default {
  auth: authApi,
  user: userApi,
  album: albumApi,
  artist: artistApi,
  song: songApi,
  playlist: playlistApi,
  search: searchApi,
  system: systemApi,
};
