import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import * as authApi from '../api/auth'
import type { UserProfile } from '../api/auth'

// Auth store：管理登录状态、用户信息、token 持久化
export const useAuthStore = defineStore('auth', () => {
  // 从 localStorage 恢复（刷新页面后保持登录态）
  const token = ref<string | null>(localStorage.getItem('linli_token'))
  const user = ref<UserProfile | null>(
    (() => {
      const raw = localStorage.getItem('linli_user')
      return raw ? (JSON.parse(raw) as UserProfile) : null
    })(),
  )

  const isLoggedIn = computed(() => !!token.value)

  function setAuth(t: string, u: UserProfile) {
    token.value = t
    user.value = u
    localStorage.setItem('linli_token', t)
    localStorage.setItem('linli_user', JSON.stringify(u))
  }

  async function doRegister(email: string, password: string, nickname: string) {
    const res = await authApi.register(email, password, nickname)
    setAuth(res.token, res.user)
  }

  async function doLogin(email: string, password: string) {
    const res = await authApi.login(email, password)
    setAuth(res.token, res.user)
  }

  function logout() {
    token.value = null
    user.value = null
    localStorage.removeItem('linli_token')
    localStorage.removeItem('linli_user')
  }

  return { token, user, isLoggedIn, doRegister, doLogin, logout }
})
