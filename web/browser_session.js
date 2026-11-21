// A read-write transaction serializes simultaneous first visits in different tabs.
window.jjakBrowserSession = () => new Promise((resolve, reject) => {
  const opening = indexedDB.open('jjak-browser', 1);
  opening.onupgradeneeded = () => opening.result.createObjectStore('session');
  opening.onerror = () => reject(opening.error);
  opening.onsuccess = () => {
    const db = opening.result;
    const tx = db.transaction('session', 'readwrite');
    const store = tx.objectStore('session');
    const reading = store.get('credential');
    let credential;
    reading.onsuccess = () => {
      if (reading.result !== undefined) {
        credential = reading.result;
        if (!/^device-v1\.[a-f0-9]{64}$/.test(credential)) tx.abort();
        return;
      }
      const bytes = crypto.getRandomValues(new Uint8Array(32));
      credential = 'device-v1.' + Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
      store.add(credential, 'credential');
    };
    tx.oncomplete = () => { db.close(); resolve(credential); };
    tx.onabort = () => { db.close(); reject(tx.error || new Error('Session storage unavailable')); };
  };
});
