export const races = {
  vael: { name:'Vael', icon:'◇', description:'Navigateurs stellaires', effect:'Puissance spatiale +15 % · puissance terrestre −15 %' },
  khar: { name:'Khar', icon:'△', description:'Gardiens des mondes', effect:'Puissance terrestre +15 % · puissance spatiale −15 %' },
  elys: { name:'Elys', icon:'◎', description:'Civilisation polyvalente', effect:'Puissances spatiale et terrestre équilibrées' }
};
export const resources = {
  aurite: { name:'Aurite', icon:'◈', description:'Cristal économique', effect:'Commerce et revenus civils locaux +15 %' },
  biomasse: { name:'Biomasse', icon:'❋', description:'Matrice biologique', effect:'Production automatique de soldats +15 %' },
  ferros: { name:'Ferros', icon:'⬡', description:'Alliage industriel', effect:'Vitesse des chantiers +15 % · durée divisée par 1,15' }
};
export const number = value => new Intl.NumberFormat('fr-FR').format(value);
export const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function validateFounding({ username, planet }) {
  if (!/^[a-zA-Z0-9_-]{3,24}$/.test(username)) return 'Pseudo : 3 à 24 lettres, chiffres, tirets ou underscores.';
  if (typeof planet !== 'string' || planet.trim().length < 3 || planet.trim().length > 40) return 'Le nom de la planète doit contenir 3 à 40 caractères.';
  return null;
}
export function planetLabel(planet, clan) {
  return `${planet.name}${planet.clan_tag_visible && clan?.name ? ` [${clan.name}]` : ''}`;
}
export function readEmailLink(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.hostname !== 'qidkgtuvcvoztzfmflgw.supabase.co' || url.pathname !== '/auth/v1/verify') throw Error('Copie le lien de confirmation complet reçu par e-mail.');
  const token_hash = url.searchParams.get('token') || url.searchParams.get('token_hash');
  const type = url.searchParams.get('type');
  if (!token_hash || !['signup','recovery','email'].includes(type)) throw Error('Ce lien ne permet pas de confirmer ton adresse ou de récupérer ton compte.');
  return { token_hash, type };
}
