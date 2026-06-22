<script setup lang="ts">
import { useAuthStore } from '../stores/auth'
import { useRouter } from 'vue-router'

const auth = useAuthStore()
const router = useRouter()

function logout() {
  auth.logout()
  router.push('/login')
}
</script>

<template>
  <div class="home">
    <header class="header">
      <h1 class="logo">林立</h1>
      <div class="user-info" v-if="auth.user">
        <span class="welcome">你好，{{ auth.user.nickname }}</span>
        <button class="btn-logout" @click="logout">退出</button>
      </div>
    </header>

    <main class="content">
      <div class="placeholder-card">
        <div class="placeholder-icon">🏃</div>
        <h2>登录成功！</h2>
        <p>这是网页版首页。后续会显示动态流、活动详情、地图轨迹等。</p>
        <div class="user-detail" v-if="auth.user">
          <p><strong>邮箱：</strong>{{ auth.user.email }}</p>
          <p><strong>昵称：</strong>{{ auth.user.nickname }}</p>
          <p><strong>注册时间：</strong>{{ new Date(auth.user.created_at).toLocaleString() }}</p>
        </div>
      </div>
    </main>
  </div>
</template>

<style scoped>
.home {
  min-height: 100vh;
  background: #f5f5f5;
}
.header {
  background: white;
  padding: 16px 24px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
}
.logo {
  color: #ff6b35;
  font-size: 22px;
  font-weight: 800;
  margin: 0;
}
.user-info {
  display: flex;
  align-items: center;
  gap: 16px;
}
.welcome {
  color: #333;
  font-size: 14px;
}
.btn-logout {
  background: none;
  border: 1px solid #ddd;
  padding: 6px 14px;
  border-radius: 6px;
  cursor: pointer;
  color: #666;
  font-size: 13px;
}
.btn-logout:hover {
  border-color: #ff6b35;
  color: #ff6b35;
}
.content {
  max-width: 720px;
  margin: 32px auto;
  padding: 0 24px;
}
.placeholder-card {
  background: white;
  border-radius: 12px;
  padding: 48px 32px;
  text-align: center;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
}
.placeholder-icon {
  font-size: 64px;
  margin-bottom: 16px;
}
.placeholder-card h2 {
  color: #333;
  margin: 0 0 8px;
}
.placeholder-card p {
  color: #9e9e9e;
  margin: 0 0 24px;
}
.user-detail {
  background: #fafafa;
  border-radius: 8px;
  padding: 16px;
  text-align: left;
  max-width: 360px;
  margin: 0 auto;
}
.user-detail p {
  margin: 8px 0;
  color: #666;
  font-size: 14px;
}
</style>
