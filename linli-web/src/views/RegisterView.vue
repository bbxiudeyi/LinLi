<script setup lang="ts">
import { ref, reactive } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const router = useRouter()
const auth = useAuthStore()

const form = reactive({
  email: '',
  password: '',
  confirmPassword: '',
  nickname: '',
})
const loading = ref(false)
const errorMsg = ref('')

async function onSubmit() {
  errorMsg.value = ''

  // 前端校验
  if (form.password !== form.confirmPassword) {
    errorMsg.value = '两次密码不一致'
    return
  }
  if (form.password.length < 8) {
    errorMsg.value = '密码至少 8 位'
    return
  }
  if (!form.nickname.trim()) {
    errorMsg.value = '请输入昵称'
    return
  }

  loading.value = true
  try {
    await auth.doRegister(form.email, form.password, form.nickname.trim())
    router.push('/')
  } catch (e: any) {
    errorMsg.value = e.response?.data?.error || '注册失败'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="auth-page">
    <div class="auth-card">
      <h1 class="title">创建账号</h1>
      <p class="subtitle">加入林立，开始记录运动</p>

      <form @submit.prevent="onSubmit" class="form">
        <div class="field">
          <label>昵称</label>
          <input v-model="form.nickname" type="text" required placeholder="你的昵称" maxlength="32" />
        </div>

        <div class="field">
          <label>邮箱</label>
          <input v-model="form.email" type="email" required placeholder="you@example.com" autocomplete="email" />
        </div>

        <div class="field">
          <label>密码</label>
          <input v-model="form.password" type="password" required placeholder="至少 8 位" autocomplete="new-password" />
        </div>

        <div class="field">
          <label>确认密码</label>
          <input v-model="form.confirmPassword" type="password" required placeholder="再输一次" autocomplete="new-password" />
        </div>

        <p v-if="errorMsg" class="error">{{ errorMsg }}</p>

        <button type="submit" class="btn-primary" :disabled="loading">
          {{ loading ? '注册中...' : '注册' }}
        </button>
      </form>

      <p class="switch-link">
        已有账号？<router-link to="/login">直接登录</router-link>
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
  font-size: 28px;
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
