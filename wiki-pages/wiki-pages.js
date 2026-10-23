(() => {
  const root = document.documentElement;
  const body = document.body;
  const indexFilter = document.querySelector('#filter');
  if (indexFilter) {
    const cards = [...document.querySelectorAll('.entry-card')];
    const categoryButtons = [...document.querySelectorAll('.category-filter')];
    const resultCount = document.createElement('p');
    resultCount.className = 'result-count';
    resultCount.setAttribute('aria-live', 'polite');
    indexFilter.insertAdjacentElement('afterend', resultCount);
    let selectedCategory = 'all';
    const normalize = (value) => (value || '').toLocaleLowerCase('fr').normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    const applyFilters = () => {
      const query = normalize(indexFilter.value.trim());
      let visible = 0;
      cards.forEach((card) => {
        const title = normalize(card.querySelector('b')?.textContent);
        const categories = (card.dataset.categories || '').split(/\s+/);
        const matches = (!query || title.includes(query)) && (selectedCategory === 'all' || categories.includes(selectedCategory));
        card.hidden = !matches;
        if (matches) visible += 1;
      });
      resultCount.textContent = `${visible} / ${cards.length} entrées affichées`;
    };
    indexFilter.oninput = applyFilters;
    indexFilter.addEventListener('input', applyFilters);
    categoryButtons.forEach((button) => button.addEventListener('click', () => {
      selectedCategory = button.dataset.category || 'all';
      categoryButtons.forEach((item) => item.classList.toggle('active', item === button));
      applyFilters();
    }));
    applyFilters();
  }
})();
