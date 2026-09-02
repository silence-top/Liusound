/**
 * Subsonic API 公共工具
 * 统一构建封面图 / 音频流等直链 URL，避免各组件重复拼接
 */

export interface SubsonicAuth {
  serverUrl: string;
  username: string;
  subsonicToken: string;
  subsonicSalt: string;
}

export const SUBSONIC_CLIENT = 'NavidromeUI';
export const SUBSONIC_API_VERSION = '1.8.0';

/** 查询参数值类型 */
type QueryValue = string | number | boolean | undefined;

/** 构建 Subsonic 公共认证参数（u/t/s/f/v/c） */
export const buildSubsonicParams = (
  auth: SubsonicAuth,
  extra: Record<string, QueryValue> = {}
): Record<string, QueryValue> => ({
  u: auth.username,
  t: auth.subsonicToken,
  s: auth.subsonicSalt,
  f: 'json',
  v: SUBSONIC_API_VERSION,
  c: SUBSONIC_CLIENT,
  ...extra,
});

/** 获取专辑/歌曲封面 URL */
export const buildCoverArtUrl = (auth: SubsonicAuth, id?: string): string => {
  if (!id || !auth.serverUrl) return '';
  return `${auth.serverUrl}/rest/getCoverArt?${toQueryString(
    buildSubsonicParams(auth, { id, size: 300, square: true })
  )}`;
};

/** 获取歌曲流媒体 URL */
export const buildStreamUrl = (auth: SubsonicAuth, songId: string): string => {
  if (!auth.serverUrl) return '';
  return `${auth.serverUrl}/rest/stream?${toQueryString(
    buildSubsonicParams(auth, { id: songId })
  )}`;
};

/** 将参数对象序列化为 query string（忽略 undefined） */
export const toQueryString = (
  params: Record<string, QueryValue>
): string =>
  Object.entries(params)
    .filter(([, value]) => value !== undefined)
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`)
    .join('&');
