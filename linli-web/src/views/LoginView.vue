<script setup lang="ts">
import { ref, reactive } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const router = useRouter()
const route = useRoute()
const auth = useAuthStore()

const form = reactive({
  email: '',
  password: '',
})
const loading = ref(false)
const errorMsg = ref('')

async function onSubmit() {
  errorMsg.value = ''
  loading.value = true
  try {
    await auth.doLogin(form.email, form.password)
    // 登录成功 → 跳回原页面或首页
    const redirect = (route.query.redirect as string) || '/'
    router.push(redirect)
  } catch (e: any) {
    errorMsg.value = e.response?.data?.error || '登录失败，请检查邮箱密码'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="auth-page">
    <div class="auth-card">
      <h1 class="title">林立</h1>
      <p class="subtitle">记录你的每一次运动</p>

      <form @submit.prevent="onSubmit" class="form">
        <div class="field">
          <label>邮箱</label>
          <input
            v-model="form.email"
            type="email"
            required
            placeholder="you@example.com"
            autocomplete="email"
          />
        </div>

        <div class="field">
          <label>密码</label>
          <input
            v-model="form.password"
            type="password"
            required
            placeholder="至少 8 位"
            autocomplete="current-password"
          />
        </div>

        <p v-if="errorMsg" class="error">{{ errorMsg }}</p>

        <button type="submit" class="btn-primary" :disabled="loading">
          {{ loading ? '登录中...' : '登录' }}
        </button>
      </form>

      <p class="switch-link">
        还没有账号？<router-link to="/register">立即注册</router-link>
      </p>
    </div>
  </div>
</template>

<style scoped>
.auth-page {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #f5f5f5;
  padding: 20px;
}
.auth-card {
  background: white;
  border-radius: 16px;
  padding: 40px 32px;
  width: 100%;
  max-width: 380px;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.06);
}
.title {
  text-align: center;
  color: #ff6b35;
  font-size: 32px;
  margin: 0 0 4px;
  font-weight: 800;
}
.subtitle {
  text-align: center;
  color: #9e9e9e;
  margin: 0 0 32px;
  font-size: 14px;
}
.form {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.field {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.field label {
  font-size: 13px;
  color: #666;
  font-weight: 500;
}
.field input {
  padding: 12px 14px;
  border: 1px solid #ddd;
  border-radius: 8px;
  font-size: 15px;
  outline: none;
  transition: border-color 0.2s;
}
.field input:focus {
  border-color: #ff6b35;
}
.error {
  color: #f44336;
  font-size: 13px;
  margin: 0;
}
.btn-primary {
  background: #ff6b35;
  color: white;
  border: none;
  padding: 14px;
  border-radius: 8px;
  font-size: 15px;
  font-weight: 600;
  cursor: pointer;
  margin-top: 8px;
  transition: background 0.2s;
}
.btn-primary:hover:not(:disabled) {
  background: #e55a2b;
}
.btn-primary:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.switch-link {
  text-align: center;
  margin-top: 24px;
  color: #9e9e9e;
  font-size: 14px;
}
.switch-link a {
  color: #ff6b35;
  text-decoration: none;
  font-weight: 500;
}
</style>
