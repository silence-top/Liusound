export interface ApiResponse<T> {
  data: T[];
  total?: number;
  page?: number;
  size?: number;
}

export interface LoginResponse {
  token: string;
  id: string;
  name: string;
  username: string;
  isAdmin: boolean;
}

export interface UserResponse {
  id: string;
  username: string;
  name: string;
  isAdmin: boolean;
  lastFMApiKey?: string;
  subsonicSalt?: string;
  subsonicToken?: string;
  playlists?: PlaylistResponse[];
}

export interface SongResponse {
  id: string;
  title: string;
  artist: string;
  album: string;
  albumId: string;
  artistId: string;
  duration: number;
  year?: number;
  genre?: string;
  size: number;
  playCount: number;
  playDate: string | null;
  rating: number;
  starred: boolean;
  starredAt: string | null;
  createdAt: string;
  updatedAt: string;
  lyrics?: string;
}

export interface PlaylistResponse {
  id: string;
  name: string;
  comment?: string;
  duration: number;
  songCount: number;
  owner: string;
  public: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface AlbumResponse {
  id: string;
  name: string;
  artist: string;
  albumArtist: string;
  artistId: string;
  albumArtistId: string;
  songCount: number;
  duration: number;
  genre: string;
  year?: number;
  compilation: boolean;
  maxYear: number;
  minYear: number;
  date?: string;
  playCount: number;
  playDate: string | null;
  rating: number;
  starred: boolean;
  starredAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface ArtistResponse {
  id: string;
  name: string;
  albumCount: number;
  songCount: number;
  rating: number;
  starred: boolean;
  starredAt: string | null;
  playCount: number;
  playDate: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface SearchResponse {
  songs: SongResponse[];
  albums: AlbumResponse[];
  artists: ArtistResponse[];
}

export interface SystemStatusResponse {
  version: string;
  buildTime: string;
  gitBranch: string;
  gitCommit: string;
  startTime: string;
  uptime: string;
  serverStart: string;
  dbUpdateTime: string;
  lastScan: string;
  scanning: boolean;
}

export interface ErrorResponse {
  error: {
    code: string;
    message: string;
  };
} 