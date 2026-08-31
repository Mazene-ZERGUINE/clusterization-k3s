<template>
  <div id="app">
    <a class="skip" href="#contenu">Aller au contenu</a>

    <header class="rail" v-if="isAuthenticated">
      <div class="rail__inner">
        <router-link to="/" class="mark" aria-label="E-TryHard, accueil">
          <span class="mark__word">E-TryHard</span>
          <span class="mark__sub">Comptoir electronique</span>
        </router-link>

        <nav class="nav" v-if="isAuthenticated" aria-label="Navigation principale">
          <router-link to="/" class="nav-link">Catalogue</router-link>
          <router-link to="/cart" class="nav-link">
            Panier
            <span class="nav-link__count" :class="{ 'is-bumped': cartBumped }">{{ cartCount }}</span>
          </router-link>
          <router-link to="/orders" class="nav-link">Commandes</router-link>
          <button @click="logout" class="logout-btn" type="button">Deconnexion</button>
        </nav>
      </div>
    </header>

    <main class="container" id="contenu">
      <!-- Afficher AuthTest si non authentifie -->
      <div v-if="!isAuthenticated" class="auth-container">
        <AuthTest @login-success="handleLoginSuccess" />
      </div>

      <!-- Afficher le contenu principal si authentifie -->
      <router-view v-else
        :key="$route.fullPath"
        :products="products"
        :cart-items="cartItems"
        @add-to-cart="addToCart"
        @remove-from-cart="removeFromCart"
        @cart-cleared="handleCartCleared"
      />
    </main>
  </div>
</template>

<script>
import { ref, onMounted } from 'vue'
import axios from 'axios'
import { useRouter } from 'vue-router'
import AuthTest from './components/AuthTest.vue'

export default {
  name: 'App',
  components: {
    AuthTest
  },
  setup() {
    const router = useRouter()
    const products = ref([])
    const cartItems = ref([])
    const cartCount = ref(0)
    const cartBumped = ref(false)
    const isAuthenticated = ref(false)

    // Signale visuellement au compteur du rail qu'il vient de changer
    const bumpCart = () => {
      cartBumped.value = false
      requestAnimationFrame(() => { cartBumped.value = true })
      setTimeout(() => { cartBumped.value = false }, 450)
    }

    // Charger les produits depuis l'API
    const loadProducts = async () => {
      try {
        const token = localStorage.getItem('token')
        const response = await axios.get('/api/products', {
          headers: {
            Authorization: `Bearer ${token}`
          }
        })
        products.value = response.data
      } catch (error) {
        console.error('Erreur chargement produits:', error)
      }
    }

    // Charger le panier depuis l'API
    const loadCart = async () => {
      try {
        const token = localStorage.getItem('token')
        const userId = localStorage.getItem('userId')
        if (!token || !userId) return

        const response = await axios.get('/api/cart', {
          headers: { 
            Authorization: `Bearer ${token}`,
            userId: userId
          }
        })
        const previous = cartCount.value
        cartItems.value = response.data.items
        cartCount.value = cartItems.value.length
        if (cartCount.value !== previous) bumpCart()
      } catch (error) {
        console.error('Erreur chargement panier:', error)
      }
    }

    // Ajouter au panier
    const addToCart = async (product) => {
      try {
    const token = localStorage.getItem('token')
    const userId = localStorage.getItem('userId')
    
    console.log('Adding to cart:', product); // Debug log

    await axios.post('/api/cart/add', {
      userId,
      productId: product._id
    }, {
      headers: {
        Authorization: `Bearer ${token}`,
        userId: userId,
        'Content-Type': 'application/json'
      }
    });
    
    // Recharger le panier après l'ajout
    await loadCart();
  } catch (error) {
    console.error('Erreur ajout au panier:', error)
  }
}
    // Supprimer du panier
    const removeFromCart = async (productId) => {
      try {
        const token = localStorage.getItem('token')
        const userId = localStorage.getItem('userId')
        await axios.delete(`/api/cart/remove/${productId}`, {
          headers: { 
            Authorization: `Bearer ${token}`,
            userId: userId
          }
        })
        await loadCart()
      } catch (error) {
        console.error('Erreur suppression du panier:', error)
      }
    }

    // Gérer le nettoyage du panier après une commande
    const handleCartCleared = async () => {
      cartItems.value = []
      cartCount.value = 0
      await loadCart() // Recharger le panier depuis le serveur
    }

    // Gérer la connexion réussie
    const handleLoginSuccess = () => {
      isAuthenticated.value = true
      loadProducts()
      loadCart()
      router.push('/')
    }

    // Gérer la déconnexion
    const logout = () => {
      localStorage.removeItem('token')
      localStorage.removeItem('userId')
      isAuthenticated.value = false
      cartItems.value = []
      cartCount.value = 0
      router.push('/')
    }

    // Vérifier l'authentification au chargement
    const checkAuth = () => {
      const token = localStorage.getItem('token')
      const userId = localStorage.getItem('userId')
      if (token && userId) {
        isAuthenticated.value = true
        loadProducts()
        loadCart()
      }
    }

    // Recharger les produits quand on revient sur la page
    router.beforeEach((to, from, next) => {
      if (to.path === '/' && isAuthenticated.value) {
        loadProducts()
      }
      next()
    })

    onMounted(() => {
      checkAuth()
    })

    return {
      products,
      cartItems,
      cartCount,
      cartBumped,
      isAuthenticated,
      handleLoginSuccess,
      logout,
      addToCart,
      removeFromCart,
      handleCartCleared
    }
  }
}
</script>

<style>
/* Rail de tete : barre encre, fixe, comme le rail d'un rayonnage */
.skip {
  position: absolute;
  left: -9999px;
  top: 0;
  z-index: 20;
  padding: 0.75rem 1rem;
  background: var(--signal);
  color: var(--ink);
  font-family: var(--font-mono);
  font-size: var(--t--1);
  text-transform: uppercase;
  letter-spacing: 0.1em;
}

.skip:focus {
  left: 0.5rem;
  top: 0.5rem;
}

.rail {
  position: sticky;
  top: 0;
  z-index: 10;
  background: var(--ink);
  color: var(--stock);
  border-bottom: 2px solid var(--ink);
}

.rail__inner {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  max-width: 1240px;
  margin: 0 auto;
  padding: 0.85rem var(--pad);
}

.mark {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  text-decoration: none;
  color: inherit;
}

.mark__word {
  font-family: var(--font-display);
  font-weight: 900;
  font-stretch: 122%;
  font-size: 1.4rem;
  line-height: 1;
  letter-spacing: -0.045em;
  text-transform: uppercase;
}

.mark__sub {
  font-family: var(--font-mono);
  font-size: 0.625rem;
  letter-spacing: 0.24em;
  text-transform: uppercase;
  color: var(--ink-faint);
}

.nav {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.25rem;
}

.nav-link {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 0.85rem;
  color: var(--stock);
  text-decoration: none;
  font-family: var(--font-mono);
  font-size: var(--t--1);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  border: 2px solid transparent;
}

.nav-link:hover { border-color: var(--ink-faint); }

.nav-link.router-link-active {
  background: var(--signal);
  border-color: var(--signal);
  color: var(--ink);
}

.nav-link__count {
  display: inline-grid;
  place-items: center;
  min-width: 1.5rem;
  height: 1.5rem;
  padding: 0 0.35rem;
  background: var(--stock);
  color: var(--ink);
  font-variant-numeric: tabular-nums;
  font-size: 0.75rem;
}

.nav-link.router-link-active .nav-link__count {
  background: var(--ink);
  color: var(--signal);
}

.nav-link__count.is-bumped { animation: count-bump 0.4s ease; }

@keyframes count-bump {
  0% { transform: scale(1); }
  35% { transform: scale(1.35); }
  100% { transform: scale(1); }
}

.logout-btn {
  margin-left: 0.5rem;
  padding: 0.5rem 0.85rem;
  background: transparent;
  color: var(--ink-faint);
  border: 2px solid #33363d;
  font-family: var(--font-mono);
  font-size: var(--t--1);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  cursor: pointer;
  transition: color 0.12s ease, border-color 0.12s ease;
}

.logout-btn:hover {
  color: var(--stock);
  border-color: var(--stock);
}

.auth-container {
  max-width: none;
  margin: 0;
}

@media (max-width: 640px) {
  .rail__inner { padding-block: 0.7rem; }
  .nav { width: 100%; }
  .nav-link { flex: 1; justify-content: center; }
  .logout-btn {
    width: 100%;
    margin-left: 0;
  }
}
</style>
