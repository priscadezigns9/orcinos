document.addEventListener('DOMContentLoaded', async () => {
  const elements = {
    apiKey: document.getElementById('apiKey'),
    toggleVisible: document.getElementById('toggleVisible'),
    defaultPlatform: document.getElementById('defaultPlatform'),
    defaultTone: document.getElementById('defaultTone'),
    saveBtn: document.getElementById('saveBtn'),
    saveStatus: document.getElementById('saveStatus'),
    usageCount: document.getElementById('usageCount')
  };

  // 1. Load current settings
  const settings = await chrome.storage.sync.get(['openaiApiKey', 'defaultPlatform', 'defaultTone']);
  if (settings.openaiApiKey) elements.apiKey.value = settings.openaiApiKey;
  if (settings.defaultPlatform) elements.defaultPlatform.value = settings.defaultPlatform;
  if (settings.defaultTone) elements.defaultTone.value = settings.defaultTone;

  // 2. Load usage
  const local = await chrome.storage.local.get(['dailyUsage', 'lastUsedDate']);
  const today = new Date().toDateString();
  const usage = local.lastUsedDate === today ? (local.dailyUsage || 0) : 0;
  elements.usageCount.innerText = `${usage} / 5`;

  // 3. Toggle password visibility
  elements.toggleVisible.addEventListener('click', () => {
    if (elements.apiKey.type === 'password') {
      elements.apiKey.type = 'text';
      elements.toggleVisible.innerText = 'Hide';
    } else {
      elements.apiKey.type = 'password';
      elements.toggleVisible.innerText = 'Show';
    }
  });

  // 4. Save settings
  elements.saveBtn.addEventListener('click', async () => {
    const newSettings = {
      openaiApiKey: elements.apiKey.value,
      defaultPlatform: elements.defaultPlatform.value,
      defaultTone: elements.defaultTone.value
    };

    await chrome.storage.sync.set(newSettings);
    
    elements.saveStatus.innerText = 'Settings saved successfully!';
    setTimeout(() => {
      elements.saveStatus.innerText = '';
    }, 3000);
  });
});
