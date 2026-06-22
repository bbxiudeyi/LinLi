import client from './client'

// 用户公开资料
export interface UserProfile {
  id: string
  email: string
  nickname: string
  avatar_url: string | null
  bio: string | null
  gender: string | null
  birthday: string | null
  weight_kg: number | null
  created_at: string
}

// 注册/登录返回
export interface AuthResponse {
  token: string
  user: UserProfile
}

export async function register(email: string, password: string, nickname: string): Promise<AuthResponse> {
  const { data } = await client.post<AuthResponse>('/auth/register', {
    email,
    password,
    nickname,
  })
  return data
}

export async function login(email: string, password: string): Promise<AuthResponse> {
  const { data } = await client.post<AuthResponse>('/auth/login', {
    email,
    password,
  })
  return data
}

export async function getMe(): Promise<UserProfile> {
  const { data } = await client.get<UserProfile>('/auth/me')
  return data
}
