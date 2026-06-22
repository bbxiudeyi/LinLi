import axios from 'axios'

// axios 实例：baseURL 用相对路径，开发期由 vite proxy 转发到后端
// 生产部署时由 Caddy/Nginx 把 /api 反代到后端
const client = axios.create({
  baseURL: '/api/v1',
  timeout: 15000,
})

// 请求拦截器：自动带上 JWT token
client.interceptors.request.use((config) => {
  const token = localStorage.getItem('linli_token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

// 响应拦截器：401 时清 token 并跳登录
client.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem('linli_token')
      localStorage.removeItem('linli_user')
      // 不在这里跳转，让路由守卫处理
    }
    return Promise.reject(err)
  },
)

export default client
