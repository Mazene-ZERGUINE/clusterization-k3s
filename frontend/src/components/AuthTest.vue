<template>
  <div class="auth-test">
    <!-- Le panneau d'accueil est une etiquette de gondole : la marque est le drapeau -->
    <section class="marquee card" aria-labelledby="marque">
      <p class="marquee__flag tag" id="marque">E-TryHard</p>

      <p class="marquee__lead">
        Le catalogue, le panier et vos commandes, derriere une seule connexion.
      </p>

      <dl class="spec">
        <div class="spec__row">
          <dt>Catalogue</dt>
          <dd>Prix et stock affiches par reference</dd>
        </div>
        <div class="spec__row">
          <dt>Panier</dt>
          <dd>Une ligne par reference, total en direct</dd>
        </div>
        <div class="spec__row">
          <dt>Commandes</dt>
          <dd>Historique, adresse et statut de livraison</dd>
        </div>
      </dl>
    </section>

    <!-- Un seul formulaire, deux modes -->
    <section class="auth-form card" v-if="!userProfile">
      <h2>Acces au comptoir</h2>

      <div class="switch" role="tablist" aria-label="Mode d'acces">
        <button
          type="button"
          role="tab"
          :aria-selected="!isRegister"
          :class="['switch__opt', { 'is-on': !isRegister }]"
          @click="setMode(false)"
        >
          Se connecter
        </button>
        <button
          type="button"
          role="tab"
          :aria-selected="isRegister"
          :class="['switch__opt', { 'is-on': isRegister }]"
          @click="setMode(true)"
        >
          Creer un compte
        </button>
      </div>

      <form @submit.prevent="submit">
        <label class="field">
          <span class="field__label">Email</span>
          <input
            v-model="form.email"
            type="email"
            class="field__input"
            placeholder="vous@exemple.fr"
            autocomplete="email"
            required
          >
        </label>

        <label class="field">
          <span class="field__label">Mot de passe</span>
          <input
            v-model="form.password"
            type="password"
            class="field__input"
            placeholder="••••••••"
            :autocomplete="isRegister ? 'new-password' : 'current-password'"
            required
          >
          <span v-if="isRegister" class="field__hint">6 caracteres minimum.</span>
        </label>

        <div v-if="error" class="notice notice--alert">
          <span class="notice__marker">!</span>
          <span>{{ error }}</span>
        </div>

        <button type="submit" class="btn btn--signal auth-form__submit" :disabled="busy">
          {{ busy ? 'Verification…' : (isRegister ? "Creer le compte" : 'Se connecter') }}
        </button>
      </form>
    </section>

    <!-- Profil connecte -->
    <section v-else class="profile card">
      <p class="eyebrow">Compte</p>
      <h2>{{ userProfile.email }}</h2>
      <button @click="logout" class="btn btn--quiet">Se deconnecter</button>
    </section>
  </div>
</template>

<script>
import axios from 'axios';

export default {
  name: 'AuthTest',
  emits: ['login-success', 'logout'],
  data() {
    return {
      isRegister: false,
      busy: false,
      error: '',
      form: {
        email: '',
        password: ''
      },
      userProfile: null
    }
  },
  methods: {
    setMode(register) {
      this.isRegister = register;
      this.error = '';
    },
    submit() {
      return this.isRegister ? this.register() : this.login();
    },
    async register() {
      this.busy = true;
      this.error = '';
      try {
        const response = await axios.post('/api/auth/register', this.form);
        localStorage.setItem('token', response.data.token);
        localStorage.setItem('userId', response.data.userId);
        await this.getProfile();
        this.$emit('login-success', response.data.userId);
      } catch (error) {
        console.error('Erreur inscription:', error);
        this.error = error.response?.data?.message
          || 'Le compte n\'a pas pu etre cree. Verifiez vos informations.';
      } finally {
        this.busy = false;
      }
    },
    async login() {
      this.busy = true;
      this.error = '';
      try {
        const response = await axios.post('/api/auth/login', this.form);
        localStorage.setItem('token', response.data.token);
        localStorage.setItem('userId', response.data.userId);
        await this.getProfile();
        this.$emit('login-success', response.data.userId);
      } catch (error) {
        console.error('Erreur connexion:', error);
        this.error = error.response?.data?.message
          || 'Email ou mot de passe incorrect.';
      } finally {
        this.busy = false;
      }
    },
    async getProfile() {
      try {
        const token = localStorage.getItem('token');
        if (!token) return;

        const response = await axios.get('/api/auth/profile', {
          headers: { Authorization: `Bearer ${token}` }
        });
        this.userProfile = response.data;
        if (this.userProfile) {
          localStorage.setItem('userId', this.userProfile._id);
          this.$emit('login-success', this.userProfile._id);
        }
      } catch (error) {
        console.error('Erreur profil:', error);
        this.handleLogout();
      }
    },
    handleLogout() {
      localStorage.removeItem('token');
      localStorage.removeItem('userId');
      this.userProfile = null;
      this.form = { email: '', password: '' };
      this.$emit('logout');
    },
    logout() {
      this.handleLogout();
      window.location.reload();
    }
  },
  mounted() {
    this.getProfile();
  }
}
</script>

<style scoped>
.auth-test {
  display: grid;
  grid-template-columns: minmax(0, 1.15fr) minmax(320px, 0.85fr);
  align-items: start;
  gap: clamp(1.75rem, 4vw, 3.5rem);
  padding-top: clamp(0.5rem, 3vw, 2rem);
}

/* --- Panneau marque --- */

.marquee {
  --card-pad: clamp(1.5rem, 3vw, 2.25rem);
  padding-top: clamp(2.5rem, 5vw, 3.5rem);
}

.marquee__flag {
  margin-left: calc(var(--card-pad) * -1 - 1rem);
  margin-bottom: clamp(1.5rem, 3vw, 2rem);
  padding: 0.5rem 1rem 0.6rem;
  font-size: clamp(2rem, 5.4vw, 3.6rem);
  white-space: nowrap;
  animation: rise 0.6s ease both;
}

.marquee__lead {
  max-width: 36ch;
  font-size: var(--t-2);
  line-height: 1.3;
  letter-spacing: -0.01em;
}

.spec {
  margin-top: clamp(1.75rem, 3vw, 2.5rem);
  border-top: 2px solid var(--ink);
}

.spec__row {
  display: grid;
  grid-template-columns: minmax(120px, 0.35fr) minmax(0, 1fr);
  gap: 1rem;
  padding: 0.85rem 0;
  border-bottom: 1px solid var(--rail-deep);
}

.spec__row dt {
  font-family: var(--font-mono);
  font-size: var(--t--2);
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: var(--ink);
}

.spec__row dd {
  font-size: var(--t--1);
  color: var(--ink-soft);
}

/* --- Formulaire --- */

.auth-form,
.profile {
  --card-pad: clamp(1.5rem, 3vw, 2rem);
}

.auth-form h2,
.profile h2 {
  margin: 0 0 1.25rem;
  font-family: var(--font-display);
  font-weight: 800;
  font-stretch: 115%;
  font-size: var(--t-3);
  line-height: 0.95;
  letter-spacing: -0.03em;
  text-transform: uppercase;
  overflow-wrap: anywhere;
}

.switch {
  display: grid;
  grid-template-columns: 1fr 1fr;
  margin-bottom: 1.5rem;
  border: 2px solid var(--ink);
}

.switch__opt {
  padding: 0.6rem 0.5rem;
  background: transparent;
  border: none;
  font-family: var(--font-mono);
  font-size: var(--t--2);
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--ink-soft);
  cursor: pointer;
  transition: background 0.12s ease, color 0.12s ease;
}

.switch__opt + .switch__opt { border-left: 2px solid var(--ink); }

.switch__opt:hover { color: var(--ink); }

.switch__opt.is-on {
  background: var(--ink);
  color: var(--stock);
}

.field__hint {
  display: block;
  margin-top: 0.35rem;
  font-family: var(--font-mono);
  font-size: var(--t--2);
  letter-spacing: 0.04em;
  color: var(--ink-soft);
}

.notice { margin-top: 1.1rem; }

.auth-form__submit {
  width: 100%;
  margin-top: 1.5rem;
}

.profile .btn { margin-top: 0.5rem; }

@media (max-width: 900px) {
  .auth-test { grid-template-columns: minmax(0, 1fr); }
  .marquee__flag { font-size: clamp(1.75rem, 9vw, 3.25rem); }
}
</style>
