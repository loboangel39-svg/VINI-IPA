// VINI V2 - Cloudflare Worker API
// Backend completo con D1 + R2
// Endpoints: /api/app/* (app iOS) + /api/admin/* + /api/* (admin panel)

// ============================================================
// BINARY PLIST PARSER (minimal — solo extrae keys del envelope .3105)
// Formato: https://opensource.apple.com/source/CF/CF-550/CFBinaryPList.c
// ============================================================

function parseBinaryPlist(buffer, baseOffset = 0) {
  // buffer es el archivo completo, baseOffset es donde empieza el bplist
  const data = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);

  // Trailer: últimos 32 bytes del archivo
  const trailerOffset = data.length - 32;
  const offsetSize = view.getUint8(trailerOffset + 6);
  const objectRefSize = view.getUint8(trailerOffset + 7);
  const objectCount = Number(view.getBigUint64(trailerOffset + 8));
  const topObject = Number(view.getBigUint64(trailerOffset + 16));
  const offsetTableOffset = Number(view.getBigUint64(trailerOffset + 24));

  // Leer offset table
  // IMPORTANTE: offsetTableOffset está calculado desde el inicio del bplist
  const offsets = [];
  for (let i = 0; i < objectCount; i++) {
    let off = 0;
    for (let j = 0; j < offsetSize; j++) {
      off = off * 256 + view.getUint8(offsetTableOffset + baseOffset + i * offsetSize + j);
    }
    offsets.push(off);
  }

  function readObject(objIndex) {
    // Los offsets están calculados desde el inicio del bplist, hay que sumar baseOffset
    const offset = offsets[objIndex] + baseOffset;
    const marker = view.getUint8(offset);
    const type = (marker >> 4) & 0x0F;
    const size = marker & 0x0F;

    switch (type) {
      case 0x00: // singleton (null/false/true)
        return size === 0 ? null : size === 8 ? false : true;
      case 0x01: { // int
        const byteCount = 1 << size;
        let val = 0;
        for (let i = 0; i < byteCount; i++) val = val * 256 + view.getUint8(offset + 1 + i);
        return val;
      }
      case 0x02: { // real
        if (size === 2) return view.getFloat32(offset + 1);
        if (size === 3) return view.getFloat64(offset + 1);
        return 0;
      }
      case 0x03: { // date
        const secs = view.getFloat64(offset + 1);
        return new Date((secs + 978307200) * 1000).toISOString();
      }
      case 0x04: { // data
        let len = size;
        let dataOff = offset + 1;
        if (len === 0x0F) {
          // Extended length: next byte is an int marker
          const extMarker = view.getUint8(dataOff);
          const extType = (extMarker >> 4) & 0x0F;
          const extSize = extMarker & 0x0F;
          if (extType === 0x01) { // int
            const byteCount = 1 << extSize;
            len = 0;
            for (let i = 0; i < byteCount; i++) {
              len = len * 256 + view.getUint8(dataOff + 1 + i);
            }
            dataOff += 1 + byteCount;
          }
        }
        return data.slice(dataOff, dataOff + len);
      }
      case 0x05: { // ascii string
        let len = size;
        let strOff = offset + 1;
        if (len === 0x0F) {
          // Extended length: next byte is an int marker
          const extMarker = view.getUint8(strOff);
          const extType = (extMarker >> 4) & 0x0F;
          const extSize = extMarker & 0x0F;
          if (extType === 0x01) { // int
            const byteCount = 1 << extSize;
            len = 0;
            for (let i = 0; i < byteCount; i++) {
              len = len * 256 + view.getUint8(strOff + 1 + i);
            }
            strOff += 1 + byteCount;
          }
        }
        let s = '';
        for (let i = 0; i < len; i++) s += String.fromCharCode(view.getUint8(strOff + i));
        return s;
      }
      case 0x06: { // unicode string
        let len = size;
        let strOff = offset + 1;
        if (len === 0x0F) {
          // Extended length: next byte is an int marker
          const extMarker = view.getUint8(strOff);
          const extType = (extMarker >> 4) & 0x0F;
          const extSize = extMarker & 0x0F;
          if (extType === 0x01) { // int
            const byteCount = 1 << extSize;
            len = 0;
            for (let i = 0; i < byteCount; i++) {
              len = len * 256 + view.getUint8(strOff + 1 + i);
            }
            strOff += 1 + byteCount;
          }
        }
        let s = '';
        for (let i = 0; i < len; i++) {
          s += String.fromCharCode(view.getUint16(strOff + i * 2));
        }
        return s;
      }
      case 0x08: { // uid
        const byteCount = size + 1;
        let val = 0;
        for (let i = 0; i < byteCount; i++) val = val * 256 + view.getUint8(offset + 1 + i);
        return val;
      }
      case 0x0A: { // array
        let len = size;
        let arrOff = offset + 1;
        if (len === 0x0F) {
          const extMarker = view.getUint8(arrOff);
          len = 1 << (extMarker & 0x0F);
          arrOff++;
        }
        const arr = [];
        for (let i = 0; i < len; i++) {
          let ref = 0;
          for (let j = 0; j < objectRefSize; j++) {
            ref = ref * 256 + view.getUint8(arrOff + i * objectRefSize + j);
          }
          arr.push(readObject(ref));
        }
        return arr;
      }
      case 0x0D: { // dict
        let len = size;
        let dictOff = offset + 1;
        if (len === 0x0F) {
          const extMarker = view.getUint8(dictOff);
          len = 1 << (extMarker & 0x0F);
          dictOff++;
        }
        const dict = {};
        // En binary plist, las keys y values están en DOS ARRAYS SEPARADOS:
        // Primero todas las keys: keyRef[0], keyRef[1], ..., keyRef[len-1]
        // Luego todos los values: valRef[0], valRef[1], ..., valRef[len-1]
        for (let i = 0; i < len; i++) {
          let keyRef = 0, valRef = 0;
          // Leer key reference
          for (let j = 0; j < objectRefSize; j++) {
            keyRef = keyRef * 256 + view.getUint8(dictOff + i * objectRefSize + j);
          }
          // Leer value reference (después de todas las keys)
          for (let j = 0; j < objectRefSize; j++) {
            valRef = valRef * 256 + view.getUint8(dictOff + len * objectRefSize + i * objectRefSize + j);
          }
          const key = readObject(keyRef);
          dict[key] = readObject(valRef);
        }
        return dict;
      }
      default:
        return null;
    }
  }

  // Root es el objeto indicado por topObject en el trailer
  return readObject(topObject);
}

// Convertir packageID a string UUID
// Puede venir como string, Uint8Array (16 bytes binarios), o UID
function packageIDToString(packageID) {
  if (typeof packageID === 'string') return packageID;
  
  if (packageID instanceof Uint8Array) {
    // UUID binario de 16 bytes → string formateado
    if (packageID.length === 16) {
      const hex = toHex(packageID);
      return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20,32)}`.toUpperCase();
    }
    // Si no es 16 bytes, convertir a hex
    return toHex(packageID);
  }
  
  // UID (número)
  return String(packageID);
}

// Extraer publicContentKey de un archivo .3105
// Si el patch no está protegido, extrae directamente publicContentKey
// Si está protegido y se proporciona password, deriva la key y desbloquea wrappedContentKey
// Retorna Uint8Array de 32 bytes o null si falla
async function extractContentKeyFrom3105(fileData, password = null) {
  const magic = new TextEncoder().encode('3105PATCH\0');
  const bytes = new Uint8Array(fileData);

  // Verificar magic
  if (bytes.length < magic.length + 20) return null;
  for (let i = 0; i < magic.length; i++) {
    if (bytes[i] !== magic[i]) return null;
  }

  // Parsear el binary plist
  // IMPORTANTE: Los offsets en el trailer están calculados desde el inicio del bplist,
  // no desde el inicio del archivo. Hay que pasar baseOffset para ajustar.
  let envelope;
  try {
    envelope = parseBinaryPlist(bytes, magic.length);
  } catch {
    return null;
  }

  // Si NO está protegido por password, extraer directamente
  if (!envelope.isPasswordProtected) {
    const key = envelope.publicContentKey;
    if (key instanceof Uint8Array && key.length === 32) return key;
    return null;
  }

  // Si está protegido pero no hay password, no podemos extraer
  if (!password || password.length === 0) return null;

  // Derivar la wrapping key desde la password
  try {
    const salt = envelope.kdfSalt;
    const iterations = envelope.kdfIterations || 100000;
    const wrappedKey = envelope.wrappedContentKey;

    if (!(salt instanceof Uint8Array) || !(wrappedKey instanceof Uint8Array)) return null;

    // Derivar key usando PBKDF2
    const derivedKey = await deriveKeyFromPassword(password, salt, iterations);

    // Desbloquear wrappedContentKey usando AES-GCM
    // El wrappedKey tiene el formato combinado: nonce (12 bytes) + ciphertext + tag (16 bytes)
    if (wrappedKey.length < 28) return null; // 12 nonce + 16 tag mínimo

    const nonce = wrappedKey.slice(0, 12);
    const ciphertext = wrappedKey.slice(12);

    // Calcular el AAD (Additional Authenticated Data) — debe coincidir con el usado por Swift
    // Swift: Data("3105PATCH/v\(version)/key/\(packageID.uuidString)".utf8)
    const packageID = envelope.packageID;
    const aadVersion = envelope.keyAADVersion || envelope.schemaVersion;
    if (!packageID || !aadVersion) return null;

    // Convertir packageID a string UUID correctamente
    const packageIDStr = packageIDToString(packageID);
    const aadString = `3105PATCH/v${aadVersion}/key/${packageIDStr}`;
    const keyAAD = new TextEncoder().encode(aadString);

    const unlockedKey = await aesGcmDecrypt(derivedKey, nonce, ciphertext, keyAAD);
    if (unlockedKey && unlockedKey.length === 32) return unlockedKey;

    return null;
  } catch (e) {
    console.error('Failed to extract content key with password:', e);
    return null;
  }
}

// Implementación manual de PBKDF2-SHA256 para soportar >100k iteraciones
// Cloudflare Workers limita crypto.subtle.deriveBits a 100,000 iteraciones
async function deriveKeyFromPassword(password, salt, iterations) {
  const encoder = new TextEncoder();
  const passwordBuffer = encoder.encode(password);

  // Importar password como HMAC key
  const hmacKey = await crypto.subtle.importKey(
    'raw',
    passwordBuffer,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );

  // PBKDF2: DK = T1 || T2 || ... donde Ti = U1 ^ U2 ^ ... ^ Uc
  // U1 = HMAC(password, salt || INT_32_BE(i))
  // Uj = HMAC(password, Uj-1)
  
  // Para 32 bytes necesitamos solo 1 bloque (T1)
  const blockIndex = new Uint8Array(4);
  blockIndex[3] = 1; // INT_32_BE(1)
  
  // Concatenar salt + blockIndex
  const saltWithIndex = new Uint8Array(salt.length + 4);
  saltWithIndex.set(salt, 0);
  saltWithIndex.set(blockIndex, salt.length);
  
  // U1 = HMAC(password, salt || INT_32_BE(1))
  let u = await crypto.subtle.sign('HMAC', hmacKey, saltWithIndex);
  let result = new Uint8Array(u);
  
  // Iteraciones restantes: U2, U3, ..., Uc
  for (let i = 1; i < iterations; i++) {
    u = await crypto.subtle.sign('HMAC', hmacKey, u);
    const uArray = new Uint8Array(u);
    // XOR: result = result ^ u
    for (let j = 0; j < result.length; j++) {
      result[j] ^= uArray[j];
    }
  }
  
  return result;
}

// Desbloquear datos usando AES-GCM
// aad = Additional Authenticated Data (debe coincidir con el usado al cifrar)
async function aesGcmDecrypt(key, nonce, ciphertextWithTag, aad = new Uint8Array(0)) {
  try {
    // Importar key para AES-GCM
    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      key,
      { name: 'AES-GCM' },
      false,
      ['decrypt']
    );

    // Decrypt (AES-GCM decrypt también verifica el tag)
    const decrypted = await crypto.subtle.decrypt(
      {
        name: 'AES-GCM',
        iv: nonce,
        tagLength: 128, // 16 bytes = 128 bits
        additionalData: aad
      },
      cryptoKey,
      ciphertextWithTag
    );

    return new Uint8Array(decrypted);
  } catch (e) {
    return null;
  }
}

// Convertir Uint8Array a hex string
function toHex(uint8Array) {
  return Array.from(uint8Array).map(b => b.toString(16).padStart(2, '0')).join('');
}

// Formatear bytes a formato legible
function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
}

// Limpiar archivos duplicados/orfanos de R2
async function cleanupR2Files(env, dryRun = true) {
  const results = {
    totalFiles: 0,
    validFiles: 0,
    orphanFiles: [],
    deletedFiles: []
  };

  // Obtener todos los archivos de R2
  const listed = await env.R2.list({ limit: 1000 });
  results.totalFiles = listed.objects.length;

  // Obtener todos los file_keys válidos de la base de datos
  const patches = await env.DB.prepare('SELECT id, file_key FROM patches').all();
  const validFileKeys = new Set(patches.results.map(p => p.file_key).filter(fk => fk));

  // Identificar archivos duplicados y orfanos
  const seenIds = new Map(); // id -> file_key
  
  for (const obj of listed.objects) {
    const key = obj.key;
    
    // Extraer ID del nombre del archivo (formato: {id}.3105 o patches/{id}/{filename})
    let patchId = null;
    if (key.includes('.3105')) {
      patchId = key.replace('.3105', '');
    } else if (key.startsWith('patches/')) {
      const parts = key.split('/');
      if (parts.length >= 2) {
        patchId = parts[1];
      }
    }

    if (patchId) {
      if (seenIds.has(patchId)) {
        // Es un duplicado
        results.orphanFiles.push({
          key: key,
          size: obj.size,
          reason: 'duplicate',
          originalKey: seenIds.get(patchId)
        });
        
        if (!dryRun) {
          await env.R2.delete(key);
          results.deletedFiles.push(key);
        }
      } else if (!validFileKeys.has(key)) {
        // Es un archivo orfano (no está en la DB)
        results.orphanFiles.push({
          key: key,
          size: obj.size,
          reason: 'orphan'
        });
        
        if (!dryRun) {
          await env.R2.delete(key);
          results.deletedFiles.push(key);
        }
      } else {
        // Archivo válido
        seenIds.set(patchId, key);
        results.validFiles++;
      }
    }
  }

  return results;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // === DEBUG STORAGE ===
    if (path === '/debug/storage' && method === 'GET') {
      const db = await env.DB.prepare('SELECT 1 AS test').first();
      return Response.json({ worker: 'OK', d1: db?.test === 1 ? 'OK' : 'ERROR' });
    }

    // === LIST R2 FILES ===
    if (path === '/debug/r2/list' && method === 'GET') {
      const listed = await env.R2.list({ limit: 1000 });
      
      // Obtener file_keys válidos de la DB
      const patches = await env.DB.prepare('SELECT id, name, file_key FROM patches').all();
      const validFileKeys = new Set(patches.results.map(p => p.file_key).filter(fk => fk));
      
      const files = listed.objects.map(obj => ({
        key: obj.key,
        size: obj.size,
        sizeFormatted: formatBytes(obj.size),
        isValid: validFileKeys.has(obj.key),
        uploaded: obj.uploaded.toISOString()
      }));

      return Response.json({
        totalFiles: files.length,
        validFiles: files.filter(f => f.isValid).length,
        orphanFiles: files.filter(f => !f.isValid).length,
        truncated: listed.truncated,
        files: files
      });
    }

    // === COUNT R2 FILES (fast) ===
    if (path === '/debug/r2/count' && method === 'GET') {
      let count = 0;
      let cursor = null;
      
      do {
        const listed = await env.R2.list({ limit: 1000, cursor });
        count += listed.objects.length;
        cursor = listed.truncated ? listed.cursor : null;
      } while (cursor);
      
      return Response.json({
        totalFiles: count
      });
    }

    // === CLEANUP R2 FILES (dry run) ===
    if (path === '/debug/r2/cleanup' && method === 'GET') {
      const results = await cleanupR2Files(env, true);
      return Response.json({
        message: 'Dry run - no files were deleted',
        ...results,
        orphanFiles: results.orphanFiles.map(f => ({
          key: f.key,
          size: f.size,
          sizeFormatted: formatBytes(f.size),
          reason: f.reason,
          originalKey: f.originalKey
        }))
      });
    }

    // === CLEANUP R2 FILES (actual delete) ===
    if (path === '/debug/r2/cleanup' && method === 'POST') {
      const results = await cleanupR2Files(env, false);
      return Response.json({
        message: 'Cleanup completed - orphan/duplicate files deleted',
        ...results
      });
    }

    // === DELETE ALL R2 FILES (nuke) ===
    if (path === '/debug/r2/nuke' && method === 'POST') {
      let deletedCount = 0;
      let cursor = null;
      
      do {
        const listed = await env.R2.list({ limit: 1000, cursor });
        
        // Borrar en lotes
        const deletePromises = listed.objects.map(obj => env.R2.delete(obj.key));
        await Promise.all(deletePromises);
        
        deletedCount += listed.objects.length;
        cursor = listed.truncated ? listed.cursor : null;
      } while (cursor);
      
      return Response.json({
        message: `Deleted ${deletedCount} files from R2`,
        deletedCount
      });
    }

    // === FIND DUPLICATE PATCHES ===
    if (path === '/debug/patches/duplicates' && method === 'GET') {
      const patches = await env.DB.prepare('SELECT id, name, created_at FROM patches ORDER BY name, created_at').all();
      
      const byName = {};
      for (const p of patches.results) {
        if (!byName[p.name]) byName[p.name] = [];
        byName[p.name].push(p);
      }
      
      const duplicates = [];
      for (const [name, list] of Object.entries(byName)) {
        if (list.length > 1) {
          duplicates.push({
            name,
            count: list.length,
            patches: list.map((p, i) => ({
              id: p.id,
              created_at: p.created_at,
              keep: i === 0 // Mantener el más antiguo
            }))
          });
        }
      }
      
      return Response.json({
        totalPatches: patches.results.length,
        duplicateGroups: duplicates.length,
        duplicates
      });
    }

    // === DELETE DUPLICATE PATCHES ===
    if (path === '/debug/patches/duplicates' && method === 'POST') {
      const patches = await env.DB.prepare('SELECT id, name, file_key, created_at FROM patches ORDER BY name, created_at').all();
      
      const byName = {};
      for (const p of patches.results) {
        if (!byName[p.name]) byName[p.name] = [];
        byName[p.name].push(p);
      }
      
      let deletedCount = 0;
      const deletedIds = [];
      
      for (const [name, list] of Object.entries(byName)) {
        if (list.length > 1) {
          // Mantener el primero (más antiguo), borrar el resto
          for (let i = 1; i < list.length; i++) {
            const p = list[i];
            
            // Borrar archivo de R2
            if (p.file_key) {
              try { await env.R2.delete(p.file_key); } catch (e) {}
            }
            
            // Borrar de la DB
            await env.DB.prepare('DELETE FROM patches WHERE id = ?').bind(p.id).run();
            await env.DB.prepare('DELETE FROM user_patches WHERE patch_id = ?').bind(p.id).run();
            await env.DB.prepare('DELETE FROM downloads WHERE patch_id = ?').bind(p.id).run();
            
            deletedCount++;
            deletedIds.push(p.id);
          }
        }
      }
      
      return Response.json({
        message: `Deleted ${deletedCount} duplicate patches`,
        deletedCount,
        deletedIds
      });
    }

    // === DEBUG HEX DUMP ===
    if (path.startsWith('/debug/patch/') && path.endsWith('/hexdump') && method === 'GET') {
      const patchId = path.split('/')[3];
      const patch = await env.DB.prepare('SELECT file_key FROM patches WHERE id = ?').bind(patchId).first();
      if (!patch || !patch.file_key) {
        return Response.json({ error: 'Patch or file not found' }, { status: 404 });
      }

      const object = await env.R2.get(patch.file_key);
      if (!object) {
        return Response.json({ error: 'File not found in R2' });
      }

      const buffer = await object.arrayBuffer();
      const bytes = new Uint8Array(buffer);
      
      // Dump first 512 bytes as hex
      const hexDump = [];
      const limit = Math.min(512, bytes.length);
      for (let i = 0; i < limit; i += 16) {
        const hex = [];
        const ascii = [];
        for (let j = 0; j < 16 && i + j < bytes.length; j++) {
          const byte = bytes[i + j];
          hex.push(byte.toString(16).padStart(2, '0'));
          ascii.push(byte >= 32 && byte < 127 ? String.fromCharCode(byte) : '.');
        }
        hexDump.push(`${i.toString(16).padStart(4, '0')}: ${hex.join(' ')}  ${ascii.join('')}`);
      }

      // Parse trailer
      const trailerOffset = bytes.length - 32;
      const view = new DataView(buffer);
      const offsetSize = view.getUint8(trailerOffset + 6);
      const objectRefSize = view.getUint8(trailerOffset + 7);
      const objectCount = Number(view.getBigUint64(trailerOffset + 8));
      const topObject = Number(view.getBigUint64(trailerOffset + 16));
      const offsetTableOffset = Number(view.getBigUint64(trailerOffset + 24));

      return Response.json({
        fileSize: bytes.length,
        magic: new TextDecoder().decode(bytes.slice(0, 10)),
        trailer: {
          offsetSize,
          objectRefSize,
          objectCount,
          topObject,
          offsetTableOffset
        },
        hexDump: hexDump.join('\n')
      });
    }

    // === TEST EXTRACTION WITH SPECIFIC PASSWORD ===
    if (path.startsWith('/debug/patch/') && path.endsWith('/test-extract') && method === 'GET') {
      const patchId = path.split('/')[3];
      const testPassword = url.searchParams.get('password') || '';
      
      const patch = await env.DB.prepare('SELECT * FROM patches WHERE id = ?').bind(patchId).first();
      if (!patch) {
        return Response.json({ error: 'Patch not found' }, { status: 404 });
      }

      const debugInfo = {
        patchId: patch.id,
        name: patch.name,
        dbPassword: patch.password || '(empty)',
        dbPasswordHex: patch.password ? toHex(new TextEncoder().encode(patch.password)) : '(empty)',
        dbPasswordLength: patch.password ? patch.password.length : 0,
        testPassword: testPassword,
        testPasswordHex: toHex(new TextEncoder().encode(testPassword)),
        testPasswordLength: testPassword.length,
      };

      if (!patch.file_key) {
        return Response.json({ ...debugInfo, error: 'No file uploaded' });
      }

      try {
        const object = await env.R2.get(patch.file_key);
        if (!object) {
          return Response.json({ ...debugInfo, error: 'File not found in R2' });
        }

        const fileBuffer = await object.arrayBuffer();
        
        // Test with DB password
        const extractedWithDb = await extractContentKeyFrom3105(fileBuffer, patch.password || null);
        debugInfo.extractedWithDbPassword = extractedWithDb ? toHex(extractedWithDb) : 'FAILED';

        // Test with provided password
        if (testPassword) {
          const extractedWithTest = await extractContentKeyFrom3105(fileBuffer, testPassword);
          debugInfo.extractedWithTestPassword = extractedWithTest ? toHex(extractedWithTest) : 'FAILED';
        }

        // Detailed step-by-step with test password
        const password = testPassword || patch.password;
        if (password) {
          const magic = new TextEncoder().encode('3105PATCH\0');
          const bytes = new Uint8Array(fileBuffer);
          const envelope = parseBinaryPlist(bytes, magic.length);
          
          const salt = envelope.kdfSalt;
          const iterations = envelope.kdfIterations || 100000;
          const wrappedKey = envelope.wrappedContentKey;
          
          debugInfo.step1_saltHex = toHex(salt);
          debugInfo.step2_iterations = iterations;
          debugInfo.step3_wrappedKeyHex = toHex(wrappedKey);
          
          // Derive key usando implementación manual (soporta >100k iteraciones)
          const passwordBuffer = new TextEncoder().encode(password);
          debugInfo.step4_passwordBufferHex = toHex(passwordBuffer);
          
          const derivedKey = await deriveKeyFromPassword(password, salt, iterations);
          debugInfo.step5_derivedKeyHex = toHex(derivedKey);
          
          // Decrypt
          const nonce = wrappedKey.slice(0, 12);
          const ciphertext = wrappedKey.slice(12);
          
          debugInfo.step6_nonceHex = toHex(nonce);
          debugInfo.step7_ciphertextLength = ciphertext.length;
          
          const packageID = envelope.packageID;
          const aadVersion = envelope.keyAADVersion || envelope.schemaVersion;
          const aadString = `3105PATCH/v${aadVersion}/key/${packageID}`;
          debugInfo.step8_aadString = aadString;
          
          const keyAAD = new TextEncoder().encode(aadString);
          debugInfo.step9_aadHex = toHex(keyAAD);
          
          try {
            const cryptoKey = await crypto.subtle.importKey(
              'raw',
              derivedKey,
              { name: 'AES-GCM' },
              false,
              ['decrypt']
            );
            
            const decrypted = await crypto.subtle.decrypt(
              {
                name: 'AES-GCM',
                iv: nonce,
                tagLength: 128,
                additionalData: keyAAD
              },
              cryptoKey,
              ciphertext
            );
            
            const unlockedKey = new Uint8Array(decrypted);
            debugInfo.step10_decryptionSuccess = true;
            debugInfo.step11_contentKeyHex = toHex(unlockedKey);
            debugInfo.success = true;
          } catch (decryptError) {
            debugInfo.step10_decryptionSuccess = false;
            debugInfo.step10_decryptError = decryptError.message;
          }
        }

        return Response.json(debugInfo);
      } catch (e) {
        return Response.json({ ...debugInfo, error: 'Exception: ' + e.message, stack: e.stack });
      }
    }

    // === DEBUG ALL PATCHES ===
    if (path === '/debug/patches' && method === 'GET') {
      const patches = await env.DB.prepare('SELECT id, name, password, content_key, file_key, created_at FROM patches ORDER BY created_at DESC').all();
      const results = [];
      
      for (const patch of patches.results) {
        const info = {
          id: patch.id,
          name: patch.name,
          hasPassword: !!patch.password && patch.password.length > 0,
          passwordLength: patch.password ? patch.password.length : 0,
          hasContentKey: !!patch.content_key && patch.content_key.length > 0,
          contentKey: patch.content_key || '(empty)',
          hasFile: !!patch.file_key,
          created_at: patch.created_at,
        };
        
        if (patch.file_key) {
          try {
            const object = await env.R2.get(patch.file_key);
            if (!object) {
              info.error = 'File not found in R2';
            } else {
              const fileBuffer = await object.arrayBuffer();
              info.fileSize = fileBuffer.byteLength;
              
              const magic = new TextEncoder().encode('3105PATCH\0');
              const bytes = new Uint8Array(fileBuffer);
              
              if (bytes.length < magic.length + 20) {
                info.error = 'File too small';
              } else {
                let magicOk = true;
                for (let i = 0; i < magic.length; i++) {
                  if (bytes[i] !== magic[i]) { magicOk = false; break; }
                }
                if (!magicOk) {
                  info.error = 'Invalid magic header';
                } else {
                  try {
                    const plistData = bytes.slice(magic.length);
                    const envelope = parseBinaryPlist(plistData);
                    info.envelopeKeys = Object.keys(envelope);
                    info.isPasswordProtected = envelope.isPasswordProtected;
                    info.packageID = envelope.packageID;
                    info.packageIDType = typeof envelope.packageID;
                    info.schemaVersion = envelope.schemaVersion;
                    info.keyAADVersion = envelope.keyAADVersion;
                    info.hasKdfSalt = envelope.kdfSalt instanceof Uint8Array;
                    info.kdfSaltLength = envelope.kdfSalt ? envelope.kdfSalt.length : 0;
                    info.hasWrappedKey = envelope.wrappedContentKey instanceof Uint8Array;
                    info.wrappedKeyLength = envelope.wrappedContentKey ? envelope.wrappedContentKey.length : 0;
                    info.hasPublicKey = envelope.publicContentKey instanceof Uint8Array;
                    info.kdfIterations = envelope.kdfIterations;
                  } catch (e) {
                    info.error = 'Parse error: ' + e.message;
                  }
                }
              }
            }
          } catch (e) {
            info.error = 'Exception: ' + e.message;
          }
        }
        
        results.push(info);
      }
      
      return Response.json({ patches: results });
    }

    // === DEBUG PATCH EXTRACTION ===
    if (path.startsWith('/debug/patch/') && method === 'GET') {
      const patchId = path.split('/')[3];
      const patch = await env.DB.prepare('SELECT * FROM patches WHERE id = ?').bind(patchId).first();
      if (!patch) {
        return Response.json({ error: 'Patch not found' }, { status: 404 });
      }

      const debugInfo = {
        patchId: patch.id,
        name: patch.name,
        hasPassword: !!patch.password && patch.password.length > 0,
        passwordLength: patch.password ? patch.password.length : 0,
        currentContentKey: patch.content_key || '(empty)',
        fileKey: patch.file_key || '(no file)',
      };

      if (!patch.file_key) {
        return Response.json({ ...debugInfo, error: 'No file uploaded' });
      }

      try {
        const object = await env.R2.get(patch.file_key);
        if (!object) {
          return Response.json({ ...debugInfo, error: 'File not found in R2' });
        }

        const fileBuffer = await object.arrayBuffer();
        debugInfo.fileSize = fileBuffer.byteLength;

        // Intentar extraer content_key
        const extracted = await extractContentKeyFrom3105(fileBuffer, patch.password || null);
        
        if (extracted) {
          debugInfo.success = true;
          debugInfo.extractedContentKey = toHex(extracted);
          debugInfo.contentKeyLength = extracted.length;
        } else {
          debugInfo.success = false;
          debugInfo.error = 'Failed to extract content_key';
          
          // Diagnosticar por qué falló
          const magic = new TextEncoder().encode('3105PATCH\0');
          const bytes = new Uint8Array(fileBuffer);
          
          if (bytes.length < magic.length + 20) {
            debugInfo.diagnostic = 'File too small';
          } else {
            // Verificar magic
            let magicOk = true;
            for (let i = 0; i < magic.length; i++) {
              if (bytes[i] !== magic[i]) { magicOk = false; break; }
            }
            if (!magicOk) {
              debugInfo.diagnostic = 'Invalid magic header (not a .3105 file)';
            } else {
              // Intentar parsear el plist
              try {
                const plistData = bytes.slice(magic.length);
                const envelope = parseBinaryPlist(plistData);
                debugInfo.diagnostic = 'Parsed envelope successfully';
                debugInfo.envelopeKeys = Object.keys(envelope);
                debugInfo.isPasswordProtected = envelope.isPasswordProtected;
                debugInfo.packageID = envelope.packageID;
                debugInfo.schemaVersion = envelope.schemaVersion;
                debugInfo.keyAADVersion = envelope.keyAADVersion;
                debugInfo.hasKdfSalt = envelope.kdfSalt instanceof Uint8Array;
                debugInfo.hasWrappedKey = envelope.wrappedContentKey instanceof Uint8Array;
                debugInfo.hasPublicKey = envelope.publicContentKey instanceof Uint8Array;
                
                if (envelope.isPasswordProtected) {
                  if (!patch.password || patch.password.length === 0) {
                    debugInfo.diagnostic += ' — Password protected but no password in DB';
                  } else {
                    debugInfo.diagnostic += ' — Password provided but extraction failed (wrong password?)';
                  }
                }
              } catch (e) {
                debugInfo.diagnostic = 'Failed to parse binary plist: ' + e.message;
              }
            }
          }
        }
      } catch (e) {
        debugInfo.error = 'Exception: ' + e.message;
      }

      return Response.json(debugInfo);
    }

    // === FORCE RE-EXTRACT CONTENT KEY ===
    if (path.startsWith('/debug/patch/') && path.endsWith('/extract') && method === 'POST') {
      const patchId = path.split('/')[3];
      const patch = await env.DB.prepare('SELECT * FROM patches WHERE id = ?').bind(patchId).first();
      if (!patch) {
        return Response.json({ error: 'Patch not found' }, { status: 404 });
      }

      if (!patch.file_key) {
        return Response.json({ error: 'No file uploaded' });
      }

      try {
        const object = await env.R2.get(patch.file_key);
        if (!object) {
          return Response.json({ error: 'File not found in R2' });
        }

        const fileBuffer = await object.arrayBuffer();
        const extracted = await extractContentKeyFrom3105(fileBuffer, patch.password || null);
        
        if (extracted) {
          const contentKeyHex = toHex(extracted);
          await env.DB.prepare('UPDATE patches SET content_key = ? WHERE id = ?')
            .bind(contentKeyHex, patchId).run();
          
          return Response.json({ 
            success: true, 
            contentKey: contentKeyHex,
            message: 'Content key extracted and saved'
          });
        } else {
          return Response.json({ 
            success: false, 
            error: 'Failed to extract content_key. Check password.'
          });
        }
      } catch (e) {
        return Response.json({ error: 'Exception: ' + e.message });
      }
    }

    // === DETAILED DEBUG EXTRACTION ===
    if (path.startsWith('/debug/patch/') && path.endsWith('/extract-debug') && method === 'GET') {
      const patchId = path.split('/')[3];
      const patch = await env.DB.prepare('SELECT * FROM patches WHERE id = ?').bind(patchId).first();
      if (!patch) {
        return Response.json({ error: 'Patch not found' }, { status: 404 });
      }

      if (!patch.file_key) {
        return Response.json({ error: 'No file uploaded' });
      }

      const debugInfo = {
        patchId: patch.id,
        name: patch.name,
        password: patch.password || '(empty)',
        passwordLength: patch.password ? patch.password.length : 0,
      };

      try {
        const object = await env.R2.get(patch.file_key);
        if (!object) {
          return Response.json({ ...debugInfo, error: 'File not found in R2' });
        }

        const fileBuffer = await object.arrayBuffer();
        const bytes = new Uint8Array(fileBuffer);
        debugInfo.fileSize = bytes.length;

        // Verificar magic
        const magic = new TextEncoder().encode('3105PATCH\0');
        debugInfo.magicHex = toHex(bytes.slice(0, 10));
        debugInfo.magicExpected = toHex(magic);
        
        let magicOk = true;
        for (let i = 0; i < magic.length; i++) {
          if (bytes[i] !== magic[i]) { magicOk = false; break; }
        }
        debugInfo.magicValid = magicOk;
        
        if (!magicOk) {
          return Response.json({ ...debugInfo, error: 'Invalid magic header' });
        }

        // Parsear binary plist
        let envelope;
        try {
          envelope = parseBinaryPlist(bytes, magic.length);
          debugInfo.envelopeParsed = true;
          debugInfo.envelopeKeys = Object.keys(envelope);
        } catch (e) {
          return Response.json({ ...debugInfo, error: 'Failed to parse binary plist: ' + e.message });
        }

        // Mostrar valores del envelope
        debugInfo.isPasswordProtected = envelope.isPasswordProtected;
        debugInfo.isPasswordProtectedType = typeof envelope.isPasswordProtected;
        
        debugInfo.packageID = envelope.packageID;
        debugInfo.packageIDType = typeof envelope.packageID;
        if (envelope.packageID instanceof Uint8Array) {
          debugInfo.packageIDHex = toHex(envelope.packageID);
          debugInfo.packageIDLength = envelope.packageID.length;
        }
        
        debugInfo.schemaVersion = envelope.schemaVersion;
        debugInfo.keyAADVersion = envelope.keyAADVersion;
        debugInfo.kdfIterations = envelope.kdfIterations;
        
        if (envelope.kdfSalt instanceof Uint8Array) {
          debugInfo.kdfSaltHex = toHex(envelope.kdfSalt);
          debugInfo.kdfSaltLength = envelope.kdfSalt.length;
        } else {
          debugInfo.kdfSaltType = typeof envelope.kdfSalt;
        }
        
        if (envelope.wrappedContentKey instanceof Uint8Array) {
          debugInfo.wrappedKeyHex = toHex(envelope.wrappedContentKey);
          debugInfo.wrappedKeyLength = envelope.wrappedContentKey.length;
        } else {
          debugInfo.wrappedKeyType = typeof envelope.wrappedContentKey;
        }
        
        if (envelope.publicContentKey instanceof Uint8Array) {
          debugInfo.publicKeyHex = toHex(envelope.publicContentKey);
          debugInfo.publicKeyLength = envelope.publicContentKey.length;
        }

        // Si no está protegido, intentar extraer directamente
        if (!envelope.isPasswordProtected) {
          if (envelope.publicContentKey instanceof Uint8Array && envelope.publicContentKey.length === 32) {
            debugInfo.success = true;
            debugInfo.extractedKeyHex = toHex(envelope.publicContentKey);
            debugInfo.method = 'direct (no password)';
          } else {
            debugInfo.error = 'Not password protected but publicContentKey invalid';
          }
          return Response.json(debugInfo);
        }

        // Si está protegido, intentar con contraseña
        if (!patch.password || patch.password.length === 0) {
          debugInfo.error = 'Password protected but no password in DB';
          return Response.json(debugInfo);
        }

        // Derivar key usando implementación manual (soporta >100k iteraciones)
        debugInfo.derivationStep = 'Starting PBKDF2';
        const salt = envelope.kdfSalt;
        const iterations = envelope.kdfIterations || 100000;
        
        try {
          const passwordBuffer = new TextEncoder().encode(patch.password);
          
          debugInfo.derivationStep = 'Deriving bits';
          const derivedKey = await deriveKeyFromPassword(patch.password, salt, iterations);
          debugInfo.derivedKeyHex = toHex(derivedKey);
          debugInfo.derivationStep = 'Key derived successfully';

          // Desbloquear wrapped key
          const wrappedKey = envelope.wrappedContentKey;
          if (wrappedKey.length < 28) {
            debugInfo.error = 'Wrapped key too short: ' + wrappedKey.length;
            return Response.json(debugInfo);
          }

          const nonce = wrappedKey.slice(0, 12);
          const ciphertext = wrappedKey.slice(12);
          debugInfo.nonceHex = toHex(nonce);
          debugInfo.ciphertextLength = ciphertext.length;

          // Construir AAD
          const packageID = envelope.packageID;
          const aadVersion = envelope.keyAADVersion || envelope.schemaVersion;
          
          let packageIDString;
          if (typeof packageID === 'string') {
            packageIDString = packageID;
          } else if (packageID instanceof Uint8Array) {
            // Convertir UUID binario a string
            const hex = toHex(packageID);
            packageIDString = `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20,32)}`.toUpperCase();
          } else {
            packageIDString = String(packageID);
          }
          
          debugInfo.packageIDString = packageIDString;
          const aadString = `3105PATCH/v${aadVersion}/key/${packageIDString}`;
          debugInfo.aadString = aadString;
          const keyAAD = new TextEncoder().encode(aadString);
          debugInfo.aadHex = toHex(keyAAD);

          // Decrypt
          debugInfo.derivationStep = 'Decrypting wrapped key';
          const cryptoKey = await crypto.subtle.importKey(
            'raw',
            derivedKey,
            { name: 'AES-GCM' },
            false,
            ['decrypt']
          );

          try {
            const decrypted = await crypto.subtle.decrypt(
              {
                name: 'AES-GCM',
                iv: nonce,
                tagLength: 128,
                additionalData: keyAAD
              },
              cryptoKey,
              ciphertext
            );

            const unlockedKey = new Uint8Array(decrypted);
            debugInfo.derivationStep = 'Decryption successful';
            
            if (unlockedKey.length === 32) {
              debugInfo.success = true;
              debugInfo.extractedKeyHex = toHex(unlockedKey);
              debugInfo.method = 'password-derived';
            } else {
              debugInfo.error = 'Decrypted key wrong length: ' + unlockedKey.length;
            }
          } catch (decryptError) {
            debugInfo.derivationStep = 'Decryption failed';
            debugInfo.decryptError = decryptError.message;
            debugInfo.error = 'AES-GCM decrypt failed. Wrong password or AAD mismatch.';
          }
        } catch (deriveError) {
          debugInfo.derivationStep = 'Key derivation failed';
          debugInfo.deriveError = deriveError.message;
          debugInfo.error = 'PBKDF2 derivation failed: ' + deriveError.message;
        }

        return Response.json(debugInfo);
      } catch (e) {
        return Response.json({ ...debugInfo, error: 'Exception: ' + e.message, stack: e.stack });
      }
    }

    // === ADMIN PANEL ===
    if ((path === '/admin' || path === '/admin.html' || path === '/admin/') && method === 'GET') {
      try {
        const adminHtml = await env.R2.get('admin-panel/index.html');
        if (adminHtml) {
          return new Response(adminHtml.body, {
            headers: {
              'Content-Type': 'text/html; charset=utf-8',
              'Cache-Control': 'no-cache'
            }
          });
        }
        return new Response('Admin panel not found', { status: 404 });
      } catch (e) {
        return new Response('Error loading admin panel: ' + e.message, { status: 500 });
      }
    }

    // CORS
    if (method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        },
      });
    }

    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Content-Type': 'application/json',
    };

    try {
      // ============================================================
      // APP ENDPOINTS (no requieren admin auth, usan license auth)
      // ============================================================

      // Validate license (login de la app)
      if (path === '/api/app/validate-license' && method === 'POST') {
        return handleAppValidateLicense(request, env, corsHeaders);
      }

      // App endpoints que requieren license auth
      if (path.startsWith('/api/app/')) {
        const appAuth = await verifyAppAuth(request, env);
        if (!appAuth.valid) {
          return Response.json({ error: 'Unauthorized', valid: false }, { status: 401, headers: corsHeaders });
        }

        // GET /api/app/config
        if (path === '/api/app/config' && method === 'GET') {
          return handleAppGetConfig(env, corsHeaders);
        }

        // GET /api/app/patches — lista de patches disponibles para el usuario
        if (path === '/api/app/patches' && method === 'GET') {
          return handleAppGetPatches(env, corsHeaders, appAuth);
        }

        // GET /api/app/patches/:id — detalle de un patch
        if (path.match(/^\/api\/app\/patches\/[^/]+$/) && method === 'GET') {
          const id = path.split('/')[4];
          return handleAppGetPatchDetail(id, env, corsHeaders, appAuth);
        }

        // GET /api/app/patches/:id/download — descargar archivo .3105
        if (path.match(/^\/api\/app\/patches\/[^/]+\/download$/) && method === 'GET') {
          const id = path.split('/')[4];
          return handleAppDownloadPatch(id, env, corsHeaders, appAuth);
        }

        // GET /api/app/messages
        if (path === '/api/app/messages' && method === 'GET') {
          return handleAppGetMessages(env, corsHeaders, appAuth);
        }

        // POST /api/app/messages/:id/ack
        if (path.match(/^\/api\/app\/messages\/[^/]+\/ack$/) && method === 'POST') {
          const id = path.split('/')[4];
          return handleAppAckMessage(id, env, corsHeaders, appAuth);
        }

        // POST /api/app/telemetry
        if (path === '/api/app/telemetry' && method === 'POST') {
          return handleAppTelemetry(request, env, corsHeaders, appAuth);
        }
      }

      // ============================================================
      // ADMIN ENDPOINTS
      // ============================================================

      if (path === '/api/admin/login' && method === 'POST') {
        return handleLogin(request, env, corsHeaders);
      }

      // Verify admin auth for all other routes
      const auth = await verifyAuth(request, env);
      if (!auth.valid) {
        return Response.json({ error: 'Unauthorized' }, { status: 401, headers: corsHeaders });
      }

      // === DASHBOARD ===
      if (path === '/api/dashboard/stats' && method === 'GET') {
        return handleDashboardStats(env, corsHeaders);
      }
      if (path === '/api/dashboard/activity' && method === 'GET') {
        return handleDashboardActivity(env, corsHeaders);
      }

      // === USERS ===
      if (path === '/api/users' && method === 'GET') {
        return handleGetUsers(env, corsHeaders, url);
      }
      if (path === '/api/users' && method === 'POST') {
        return handleCreateUser(request, env, corsHeaders);
      }
      if (path.match(/^\/api\/users\/[^/]+$/) && method === 'PUT') {
        const id = path.split('/')[3];
        return handleUpdateUser(id, request, env, corsHeaders);
      }
      if (path.match(/^\/api\/users\/[^/]+\/pause$/) && method === 'POST') {
        const id = path.split('/')[3];
        return handleTogglePause(id, env, corsHeaders);
      }
      if (path.match(/^\/api\/users\/[^/]+\/hwid$/) && method === 'POST') {
        const id = path.split('/')[3];
        return handleResetHWID(id, env, corsHeaders);
      }
      if (path.match(/^\/api\/users\/[^/]+\/block$/) && method === 'POST') {
        const id = path.split('/')[3];
        return handleToggleBlock(id, env, corsHeaders);
      }
      if (path.match(/^\/api\/users\/[^/]+\/renew$/) && method === 'POST') {
        const id = path.split('/')[3];
        return handleRenewLicense(id, request, env, corsHeaders);
      }
      if (path.match(/^\/api\/users\/[^/]+$/) && method === 'DELETE') {
        const id = path.split('/')[3];
        return handleDeleteUser(id, env, corsHeaders);
      }

      // === PATCHES ===
      if (path === '/api/patches' && method === 'GET') {
        return handleGetPatches(env, corsHeaders, url);
      }
      if (path === '/api/patches' && method === 'POST') {
        return handleCreatePatch(request, env, corsHeaders);
      }
      if (path.match(/^\/api\/patches\/[^/]+$/) && method === 'PUT') {
        const id = path.split('/')[3];
        return handleUpdatePatch(id, request, env, corsHeaders);
      }
      if (path.match(/^\/api\/patches\/[^/]+$/) && method === 'DELETE') {
        const id = path.split('/')[3];
        return handleDeletePatch(id, env, corsHeaders);
      }
      if (path.match(/^\/api\/patches\/[^/]+\/toggle$/) && method === 'POST') {
        const id = path.split('/')[3];
        return handleTogglePatch(id, env, corsHeaders);
      }

      // === ACCESS ===
      if (path === '/api/access' && method === 'GET') {
        return handleGetAccess(env, corsHeaders);
      }
      if (path === '/api/access' && method === 'POST') {
        return handleGrantAccess(request, env, corsHeaders);
      }
      if (path === '/api/access' && method === 'DELETE') {
        return handleRevokeAccess(request, env, corsHeaders);
      }

      // === MESSAGES ===
      if (path === '/api/messages' && method === 'GET') {
        return handleGetMessages(env, corsHeaders);
      }
      if (path === '/api/messages' && method === 'POST') {
        return handleCreateMessage(request, env, corsHeaders);
      }
      if (path.match(/^\/api\/messages\/[^/]+$/) && method === 'PUT') {
        const id = path.split('/')[3];
        return handleUpdateMessage(id, request, env, corsHeaders);
      }
      if (path.match(/^\/api\/messages\/[^/]+$/) && method === 'DELETE') {
        const id = path.split('/')[3];
        return handleDeleteMessage(id, env, corsHeaders);
      }
      if (path.match(/^\/api\/messages\/[^/]+\/toggle$/) && method === 'POST') {
        const id = path.split('/')[3];
        return handleToggleMessage(id, env, corsHeaders);
      }

      // === STATS ===
      if (path === '/api/stats' && method === 'GET') {
        return handleStats(env, corsHeaders, url);
      }

      // === ACTIVITY LOG ===
      if (path === '/api/activity' && method === 'GET') {
        return handleGetActivity(env, corsHeaders, url);
      }

      // === CONFIG ===
      if (path === '/api/config' && method === 'GET') {
        return handleGetConfig(env, corsHeaders);
      }
      if (path === '/api/config' && method === 'PUT') {
        return handleUpdateConfig(request, env, corsHeaders);
      }

      return Response.json({ error: 'Not found' }, { status: 404, headers: corsHeaders });
    } catch (err) {
      return Response.json({ error: err.message }, { status: 500, headers: corsHeaders });
    }
  },
};

// ============================================================
// APP AUTH — Verifica license_key via Bearer token
// ============================================================

async function verifyAppAuth(request, env) {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) return { valid: false };

  const token = authHeader.split(' ')[1];

  // El token es un JWT simple que contiene { userId, licenseKey, hwid, exp }
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return { valid: false };
    const payload = JSON.parse(atob(parts[1]));
    if (payload.exp < Date.now()) return { valid: false };

    const secret = env.JWT_SECRET || 'vini-jwt-secret-change-me';
    const expectedSig = await hmacSign(`${parts[0]}.${parts[1]}`, secret);
    if (expectedSig !== parts[2]) return { valid: false };

    // Verificar que el usuario sigue activo
    const user = await env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(payload.userId).first();
    if (!user) return { valid: false };
    if (!user.is_active || user.is_paused || user.is_blocked) return { valid: false };

    return { valid: true, userId: payload.userId, hwid: payload.hwid, user };
  } catch {
    return { valid: false };
  }
}

// ============================================================
// APP ENDPOINTS HANDLERS
// ============================================================

// POST /api/app/validate-license
async function handleAppValidateLicense(request, env, headers) {
  const { licenseKey, hwid } = await request.json();

  if (!licenseKey) {
    return Response.json({ valid: false, error: 'License key required' }, { status: 400, headers });
  }

  // Buscar usuario por license_key
  const user = await env.DB.prepare('SELECT * FROM users WHERE license_key = ?').bind(licenseKey).first();

  if (!user) {
    return Response.json({ valid: false, error: 'Invalid license key' }, { status: 401, headers });
  }

  // Verificar estado
  if (!user.is_active) {
    return Response.json({ valid: false, error: 'Account inactive' }, { status: 403, headers });
  }
  if (user.is_blocked) {
    return Response.json({ valid: false, error: 'Account blocked' }, { status: 403, headers });
  }
  if (user.is_paused) {
    return Response.json({ valid: false, error: 'Account paused' }, { status: 403, headers });
  }

  // Verificar expiración de licencia
  if (user.license_expires_at) {
    const expiresAt = new Date(user.license_expires_at);
    if (expiresAt < new Date()) {
      return Response.json({ 
        valid: false, 
        error: 'License expired',
        expiredAt: user.license_expires_at 
      }, { status: 403, headers });
    }
  }

  // Verificar HWID
  if (user.hwid && user.hwid !== '' && user.hwid !== hwid) {
    return Response.json({ valid: false, error: 'HWID mismatch. Contact admin to reset.' }, { status: 403, headers });
  }

  // Registrar HWID si no está registrado
  if (!user.hwid || user.hwid === '') {
    await env.DB.prepare('UPDATE users SET hwid = ? WHERE id = ?').bind(hwid, user.id).run();
  }

  // Generar token de sesión (24h)
  const exp = Date.now() + 86400000; // 24 horas
  const token = await createJWT({ userId: user.id, licenseKey, hwid, exp }, env);

  // Registrar actividad
  await logActivity(env, 'app_login', `User ${user.username} logged in`);

  return Response.json({
    valid: true,
    token,
    expiresAt: new Date(exp).toISOString(),
    username: user.username,
    isPremium: !!user.is_premium,
    licenseExpiresAt: user.license_expires_at || null,
  }, { headers });
}

// GET /api/app/config
async function handleAppGetConfig(env, headers) {
  const result = await env.DB.prepare('SELECT key, value FROM config').all();
  const config = {};
  result.results.forEach(r => { config[r.key] = r.value; });
  return Response.json(config, { headers });
}

// GET /api/app/patches — lista de patches disponibles para el usuario
async function handleAppGetPatches(env, headers, appAuth) {
  // Obtener patches activos a los que el usuario tiene acceso
  const result = await env.DB.prepare(`
    SELECT p.id, p.name, p.description, p.version, p.type, p.file_key, p.password, p.content_key, p.created_at, p.updated_at
    FROM patches p
    INNER JOIN user_patches up ON up.patch_id = p.id
    WHERE p.active = 1
      AND up.user_id = ?
    ORDER BY p.created_at DESC
  `).bind(appAuth.userId).all();

  const patches = result.results.map(p => ({
    id: p.id,
    name: p.name,
    description: p.description,
    version: p.version,
    type: p.type,
    status: 'available',
    password: p.password || null,
    content_key: p.content_key || null,
    created_at: p.created_at,
    updated_at: p.updated_at,
  }));

  return Response.json({ patches }, { headers });
}

// GET /api/app/patches/:id — detalle de un patch
async function handleAppGetPatchDetail(id, env, headers, appAuth) {
  const patch = await env.DB.prepare(`
    SELECT p.* FROM patches p
    INNER JOIN user_patches up ON up.patch_id = p.id
    WHERE p.id = ? AND up.user_id = ? AND p.active = 1
  `).bind(id, appAuth.userId).first();

  if (!patch) {
    return Response.json({ error: 'Patch not found or access denied' }, { status: 404, headers });
  }

  return Response.json({
    id: patch.id,
    name: patch.name,
    description: patch.description,
    version: patch.version,
    type: patch.type,
    status: 'available',
    file_size: patch.file_key ? 'unknown' : 0,
    password: patch.password || null,
    content_key: patch.content_key || null,
    created_at: patch.created_at,
    updated_at: patch.updated_at,
  }, { headers });
}

// GET /api/app/patches/:id/download — descargar archivo .3105 desde R2
// REGLA PRINCIPAL: No se bloquea por descargas anteriores.
// Solo se verifica: licencia activa + permiso de acceso al patch.
async function handleAppDownloadPatch(id, env, headers, appAuth) {
  // 1. Verificar que el patch existe y el usuario tiene acceso
  const patch = await env.DB.prepare(`
    SELECT p.* FROM patches p
    INNER JOIN user_patches up ON up.patch_id = p.id
    WHERE p.id = ? AND up.user_id = ? AND p.active = 1
  `).bind(id, appAuth.userId).first();
  if (!patch) {
    return Response.json({ error: 'Patch not found or access denied' }, { status: 404, headers });
  }

  if (!patch.file_key) {
    return Response.json({ error: 'Patch has no file' }, { status: 400, headers });
  }

  // 2. Obtener archivo desde R2
  const object = await env.R2.get(patch.file_key);
  if (!object) {
    return Response.json({ error: 'File not found in storage' }, { status: 404, headers });
  }

  // 3. Registrar descarga (siempre, sin importar si ya descargó antes)
  const downloadId = crypto.randomUUID();
  await env.DB.prepare(
    'INSERT INTO downloads (id, user_id, patch_id, created_at) VALUES (?, ?, ?, ?)'
  ).bind(downloadId, appAuth.userId, id, new Date().toISOString()).run();

  // 4. Devolver el archivo como stream
  const filename = patch.file_key.split('/').pop() || `patch_${id}.3105`;
  const responseHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Content-Type': 'application/octet-stream',
    'Content-Disposition': `attachment; filename="${filename}"`,
    'Content-Length': String(object.size),
    'X-Patch-Id': id,
    'X-Patch-Version': patch.version,
    'X-Patch-Name': patch.name,
  };

  // Enviar content_key si está disponible (para desbloqueo automático en el cliente)
  if (patch.content_key && patch.content_key !== '') {
    responseHeaders['X-Content-Key'] = patch.content_key;
  }

  // Enviar contraseña si el patch está protegido (para decodificación en el cliente)
  if (patch.password && patch.password !== '') {
    responseHeaders['X-Patch-Password'] = patch.password;
  }

  return new Response(object.body, { headers: responseHeaders });
}

// GET /api/app/messages
async function handleAppGetMessages(env, headers, appAuth) {
  const result = await env.DB.prepare(`
    SELECT id, title, content, type, created_at
    FROM messages
    WHERE active = 1
      AND (target_hwid IS NULL OR target_hwid = '' OR target_hwid = ?)
    ORDER BY created_at DESC
  `).bind(appAuth.hwid).all();

  return Response.json({ messages: result.results }, { headers });
}

// POST /api/app/messages/:id/ack
async function handleAppAckMessage(id, env, headers, appAuth) {
  // Los ACK se podrían guardar en una tabla, pero por ahora solo registramos actividad
  await logActivity(env, 'message_ack', `User ${appAuth.userId} ack message ${id}`);
  return Response.json({ success: true }, { headers });
}

// POST /api/app/telemetry
async function handleAppTelemetry(request, env, headers, appAuth) {
  const data = await request.json();
  const action = data.action || 'unknown';
  const details = JSON.stringify(data);
  await logActivity(env, `telemetry_${action}`, details);
  return Response.json({ success: true }, { headers });
}

// ============================================================
// ADMIN AUTH HELPERS
// ============================================================

async function handleLogin(request, env, headers) {
  const { username, password } = await request.json();
  const adminUser = env.ADMIN_USERNAME || 'admin';
  const adminPass = env.ADMIN_PASSWORD || 'vini2026';

  if (username === adminUser && password === adminPass) {
    const token = await createJWT({ user: username, exp: Date.now() + 86400000 }, env);
    return Response.json({ token, username }, { headers });
  }
  return Response.json({ error: 'Invalid credentials' }, { status: 401, headers });
}

async function createJWT(payload, env) {
  const secret = env.JWT_SECRET || 'vini-jwt-secret-change-me';
  const header = btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = btoa(JSON.stringify(payload));
  const signature = await hmacSign(`${header}.${body}`, secret);
  return `${header}.${body}.${signature}`;
}

async function verifyAuth(request, env) {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) return { valid: false };

  const token = authHeader.split(' ')[1];
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return { valid: false };
    const payload = JSON.parse(atob(parts[1]));
    if (payload.exp < Date.now()) return { valid: false };

    const secret = env.JWT_SECRET || 'vini-jwt-secret-change-me';
    const expectedSig = await hmacSign(`${parts[0]}.${parts[1]}`, secret);
    if (expectedSig !== parts[2]) return { valid: false };

    return { valid: true, user: payload.user };
  } catch {
    return { valid: false };
  }
}

async function hmacSign(data, secret) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(data));
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

// ============================================================
// LOG ACTIVITY
// ============================================================

async function logActivity(env, action, details) {
  await env.DB.prepare(
    'INSERT INTO activity_log (action, details, created_at) VALUES (?, ?, ?)'
  ).bind(action, details, new Date().toISOString()).run();
}

// ============================================================
// ADMIN DASHBOARD
// ============================================================

async function handleDashboardStats(env, headers) {
  const users = await env.DB.prepare('SELECT COUNT(*) as count FROM users').first();
  const patches = await env.DB.prepare('SELECT COUNT(*) as count FROM patches').first();
  const activePatches = await env.DB.prepare('SELECT COUNT(*) as count FROM patches WHERE active = 1').first();
  const downloads = await env.DB.prepare('SELECT COUNT(*) as count FROM downloads').first();

  return Response.json({
    totalUsers: users.count,
    totalPatches: patches.count,
    activePatches: activePatches.count,
    totalDownloads: downloads.count,
  }, { headers });
}

async function handleDashboardActivity(env, headers) {
  const result = await env.DB.prepare(
    'SELECT * FROM activity_log ORDER BY created_at DESC LIMIT 10'
  ).all();
  return Response.json(result.results, { headers });
}

// ============================================================
// ADMIN USERS
// ============================================================

async function handleGetUsers(env, headers, url) {
  const search = url.searchParams.get('search') || '';
  let query = 'SELECT * FROM users';
  if (search) query += ` WHERE username LIKE '%${search}%' OR hwid LIKE '%${search}%'`;
  query += ' ORDER BY created_at DESC';
  const result = await env.DB.prepare(query).all();
  return Response.json(result.results, { headers });
}

async function handleCreateUser(request, env, headers) {
  const data = await request.json();
  const id = crypto.randomUUID();
  const now = new Date().toISOString();

  await env.DB.prepare(
    `INSERT INTO users (id, username, hwid, license_key, is_premium, is_active, is_paused, is_blocked, permissions, license_expires_at, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 1, 0, 0, ?, ?, ?, ?)`
  ).bind(
    id, data.username, data.hwid || '', data.licenseKey || '',
    data.isPremium ? 1 : 0, data.permissions || '{}', data.licenseExpiresAt || null, now, now
  ).run();

  await logActivity(env, 'user_created', `User ${data.username} created`);
  return Response.json({ id, ...data }, { headers });
}

async function handleUpdateUser(id, request, env, headers) {
  const data = await request.json();
  const now = new Date().toISOString();

  await env.DB.prepare(
    `UPDATE users SET username = ?, hwid = ?, license_key = ?, is_premium = ?, permissions = ?, updated_at = ? WHERE id = ?`
  ).bind(data.username, data.hwid || '', data.licenseKey || '',
    data.isPremium ? 1 : 0, data.permissions || '{}', now, id
  ).run();

  await logActivity(env, 'user_updated', `User ${id} updated`);
  return Response.json({ success: true }, { headers });
}

async function handleTogglePause(id, env, headers) {
  const user = await env.DB.prepare('SELECT is_paused FROM users WHERE id = ?').bind(id).first();
  const newState = user.is_paused ? 0 : 1;
  await env.DB.prepare('UPDATE users SET is_paused = ? WHERE id = ?').bind(newState, id).run();
  await logActivity(env, 'user_paused', `User ${id} ${newState ? 'paused' : 'resumed'}`);
  return Response.json({ is_paused: newState }, { headers });
}

async function handleResetHWID(id, env, headers) {
  await env.DB.prepare('UPDATE users SET hwid = ? WHERE id = ?').bind('', id).run();
  await logActivity(env, 'hwid_reset', `User ${id} HWID reset`);
  return Response.json({ success: true }, { headers });
}

async function handleToggleBlock(id, env, headers) {
  const user = await env.DB.prepare('SELECT is_blocked FROM users WHERE id = ?').bind(id).first();
  const newState = user.is_blocked ? 0 : 1;
  await env.DB.prepare('UPDATE users SET is_blocked = ? WHERE id = ?').bind(newState, id).run();
  await logActivity(env, 'user_blocked', `User ${id} ${newState ? 'blocked' : 'unblocked'}`);
  return Response.json({ is_blocked: newState }, { headers });
}

async function handleRenewLicense(id, request, env, headers) {
  const data = await request.json();
  const days = parseInt(data.days) || 30;
  const user = await env.DB.prepare('SELECT username, license_expires_at FROM users WHERE id = ?').bind(id).first();
  
  if (!user) {
    return Response.json({ error: 'User not found' }, { status: 404, headers });
  }

  // Calculate new expiration date
  let newExpiresAt;
  if (user.license_expires_at) {
    // If there's an existing expiration date, extend from that date (or from now if expired)
    const existingDate = new Date(user.license_expires_at);
    const now = new Date();
    const baseDate = existingDate > now ? existingDate : now;
    newExpiresAt = new Date(baseDate.getTime() + (days * 24 * 60 * 60 * 1000)).toISOString();
  } else {
    // If no expiration date, set from now
    newExpiresAt = new Date(Date.now() + (days * 24 * 60 * 60 * 1000)).toISOString();
  }

  const now = new Date().toISOString();
  await env.DB.prepare('UPDATE users SET license_expires_at = ?, updated_at = ? WHERE id = ?')
    .bind(newExpiresAt, now, id).run();
  
  await logActivity(env, 'license_renewed', `User ${user.username} license renewed for ${days} days (expires: ${newExpiresAt})`);
  return Response.json({ 
    success: true, 
    license_expires_at: newExpiresAt,
    days_added: days
  }, { headers });
}

async function handleDeleteUser(id, env, headers) {
  const user = await env.DB.prepare('SELECT username FROM users WHERE id = ?').bind(id).first();
  
  if (!user) {
    return Response.json({ error: 'User not found' }, { status: 404, headers });
  }

  // Delete all related data
  await env.DB.prepare('DELETE FROM downloads WHERE user_id = ?').bind(id).run();
  await env.DB.prepare('DELETE FROM user_patches WHERE user_id = ?').bind(id).run();
  await env.DB.prepare('DELETE FROM users WHERE id = ?').bind(id).run();
  
  await logActivity(env, 'user_deleted', `User ${user.username} (${id}) deleted`);
  return Response.json({ success: true }, { headers });
}

// ============================================================
// ADMIN PATCHES
// ============================================================

async function handleGetPatches(env, headers, url) {
  const type = url.searchParams.get('type') || '';
  const active = url.searchParams.get('active') || '';
  let query = 'SELECT * FROM patches';
  const conditions = [];
  if (type) conditions.push(`type = '${type}'`);
  if (active === '1') conditions.push('active = 1');
  if (conditions.length > 0) query += ' WHERE ' + conditions.join(' AND ');
  query += ' ORDER BY created_at DESC';
  const result = await env.DB.prepare(query).all();
  return Response.json(result.results, { headers });
}

async function handleCreatePatch(request, env, headers) {
  const formData = await request.formData();
  const id = crypto.randomUUID();
  const name = formData.get('name');
  const description = formData.get('description') || '';
  const version = formData.get('version') || '1.0.0';
  const type = formData.get('type') || 'free';
  const password = formData.get('password') || '';
  const file = formData.get('file');

  let fileKey = '';

  // 1. Subir archivo a R2
  if (file && file.size > 0) {
    fileKey = `${id}.3105`;
    const fileBuffer = await file.arrayBuffer();
    await env.R2.put(fileKey, fileBuffer);
  }

  // 2. Insertar en base de datos
  try {
    const now = new Date().toISOString();
    await env.DB.prepare(
      `INSERT INTO patches (id, name, description, version, type, file_key, content_key, password, active, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)`
    ).bind(id, name, description, version, type, fileKey, '', password, now, now).run();
  } catch (dbError) {
    // Si el INSERT falla, borrar el archivo de R2 para no dejar huérfanos
    if (fileKey) {
      try { await env.R2.delete(fileKey); } catch (e) { /* ignore */ }
    }
    console.error('Failed to insert patch in DB:', dbError);
    return Response.json({ 
      error: 'Error al guardar en base de datos: ' + dbError.message 
    }, { status: 500, headers });
  }

  // 3. Log de actividad (no crítico, no falla si hay error)
  try {
    await logActivity(env, 'patch_created', `Patch "${name}" created`);
  } catch (e) {
    console.error('Failed to log activity:', e);
  }

  return Response.json({ 
    id, 
    name, 
    version, 
    type, 
    hasContentKey: false,
    contentKeyExtracted: false,
    passwordSaved: !!password
  }, { headers });
}

async function handleUpdatePatch(id, request, env, headers) {
  const formData = await request.formData();
  const name = formData.get('name');
  const description = formData.get('description') || '';
  const version = formData.get('version') || '1.0.0';
  const type = formData.get('type') || 'free';
  const password = formData.get('password');
  const file = formData.get('file');

  let patch = await env.DB.prepare('SELECT file_key, password FROM patches WHERE id = ?').bind(id).first();

  let fileKey = patch?.file_key || '';
  let newFileKey = '';
  // Usar la password del formulario si se proporciona, sino usar la existente
  const effectivePassword = password !== null ? password : (patch?.password || '');

  // 1. Subir nuevo archivo si existe
  if (file && file.size > 0) {
    newFileKey = `${id}.3105`;
    const fileBuffer = await file.arrayBuffer();
    await env.R2.put(newFileKey, fileBuffer);
    fileKey = newFileKey;
  }

  // 2. Actualizar base de datos
  try {
    const now = new Date().toISOString();
    await env.DB.prepare(
      `UPDATE patches SET name = ?, description = ?, version = ?, type = ?, file_key = ?, password = ?, updated_at = ? WHERE id = ?`
    ).bind(name, description, version, type, fileKey, effectivePassword, now, id).run();
  } catch (dbError) {
    // Si el UPDATE falla, borrar el nuevo archivo de R2
    if (newFileKey) {
      try { await env.R2.delete(newFileKey); } catch (e) { /* ignore */ }
    }
    console.error('Failed to update patch in DB:', dbError);
    return Response.json({ 
      error: 'Error al actualizar en base de datos: ' + dbError.message 
    }, { status: 500, headers });
  }

  // 3. Borrar archivo viejo solo si el UPDATE fue exitoso
  if (newFileKey && patch.file_key && patch.file_key !== newFileKey) {
    try { await env.R2.delete(patch.file_key); } catch (e) { /* ignore */ }
  }

  // 4. Log de actividad
  try {
    await logActivity(env, 'patch_updated', `Patch ${id} updated`);
  } catch (e) {
    console.error('Failed to log activity:', e);
  }

  return Response.json({ 
    success: true,
    hasContentKey: false,
    contentKeyExtracted: false,
    passwordSaved: !!effectivePassword
  }, { headers });
}

async function handleDeletePatch(id, env, headers) {
  const patch = await env.DB.prepare('SELECT file_key, name FROM patches WHERE id = ?').bind(id).first();
  
  // 1. Borrar de base de datos primero
  try {
    await env.DB.prepare('DELETE FROM downloads WHERE patch_id = ?').bind(id).run();
    await env.DB.prepare('DELETE FROM user_patches WHERE patch_id = ?').bind(id).run();
    await env.DB.prepare('DELETE FROM patches WHERE id = ?').bind(id).run();
  } catch (dbError) {
    console.error('Failed to delete patch from DB:', dbError);
    return Response.json({ 
      error: 'Error al eliminar de base de datos: ' + dbError.message 
    }, { status: 500, headers });
  }

  // 2. Solo si el DELETE fue exitoso, borrar archivo de R2
  if (patch?.file_key) {
    try { await env.R2.delete(patch.file_key); } catch (e) { /* file may not exist in R2 */ }
  }

  // 3. Log de actividad
  try {
    await logActivity(env, 'patch_deleted', `Patch "${patch?.name || id}" deleted`);
  } catch (e) {
    console.error('Failed to log activity:', e);
  }

  return Response.json({ success: true }, { headers });
}

async function handleTogglePatch(id, env, headers) {
  const patch = await env.DB.prepare('SELECT active FROM patches WHERE id = ?').bind(id).first();
  const newState = patch.active ? 0 : 1;
  await env.DB.prepare('UPDATE patches SET active = ? WHERE id = ?').bind(newState, id).run();
  await logActivity(env, 'patch_toggled', `Patch ${id} ${newState ? 'activated' : 'deactivated'}`);
  return Response.json({ active: newState }, { headers });
}

// ============================================================
// ADMIN ACCESS
// ============================================================

async function handleGetAccess(env, headers) {
  const result = await env.DB.prepare(
    `SELECT up.*, u.username, p.name as patch_name 
     FROM user_patches up 
     JOIN users u ON up.user_id = u.id 
     JOIN patches p ON up.patch_id = p.id 
     ORDER BY up.created_at DESC`
  ).all();
  return Response.json(result.results, { headers });
}

async function handleGrantAccess(request, env, headers) {
  const { userId, patchId } = await request.json();
  const now = new Date().toISOString();

  await env.DB.prepare(
    'INSERT OR IGNORE INTO user_patches (user_id, patch_id, created_at) VALUES (?, ?, ?)'
  ).bind(userId, patchId, now).run();

  await logActivity(env, 'access_granted', `Access granted: user ${userId} -> patch ${patchId}`);
  return Response.json({ success: true }, { headers });
}

async function handleRevokeAccess(request, env, headers) {
  const { userId, patchId } = await request.json();
  await env.DB.prepare(
    'DELETE FROM user_patches WHERE user_id = ? AND patch_id = ?'
  ).bind(userId, patchId).run();

  await logActivity(env, 'access_revoked', `Access revoked: user ${userId} -> patch ${patchId}`);
  return Response.json({ success: true }, { headers });
}

// ============================================================
// ADMIN MESSAGES
// ============================================================

async function handleGetMessages(env, headers) {
  const result = await env.DB.prepare('SELECT * FROM messages ORDER BY created_at DESC').all();
  return Response.json(result.results, { headers });
}

async function handleCreateMessage(request, env, headers) {
  const data = await request.json();
  const id = crypto.randomUUID();
  const now = new Date().toISOString();

  await env.DB.prepare(
    `INSERT INTO messages (id, title, content, type, target_hwid, active, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 1, ?, ?)`
  ).bind(id, data.title, data.content, data.type || 'info', data.targetHwid || null, now, now).run();

  await logActivity(env, 'message_created', `Message "${data.title}" created`);
  return Response.json({ id }, { headers });
}

async function handleUpdateMessage(id, request, env, headers) {
  const data = await request.json();
  const now = new Date().toISOString();

  await env.DB.prepare(
    `UPDATE messages SET title = ?, content = ?, type = ?, target_hwid = ?, updated_at = ? WHERE id = ?`
  ).bind(data.title, data.content, data.type, data.targetHwid || null, now, id).run();

  return Response.json({ success: true }, { headers });
}

async function handleDeleteMessage(id, env, headers) {
  await env.DB.prepare('DELETE FROM messages WHERE id = ?').bind(id).run();
  await logActivity(env, 'message_deleted', `Message ${id} deleted`);
  return Response.json({ success: true }, { headers });
}

async function handleToggleMessage(id, env, headers) {
  const msg = await env.DB.prepare('SELECT active FROM messages WHERE id = ?').bind(id).first();
  const newState = msg.active ? 0 : 1;
  await env.DB.prepare('UPDATE messages SET active = ? WHERE id = ?').bind(newState, id).run();
  return Response.json({ active: newState }, { headers });
}

// ============================================================
// ADMIN STATS
// ============================================================

async function handleStats(env, headers, url) {
  const type = url.searchParams.get('type') || 'all';

  if (type === 'downloads') {
    const result = await env.DB.prepare(
      `SELECT DATE(created_at) as date, COUNT(*) as count 
       FROM downloads 
       WHERE created_at > datetime('now', '-30 days')
       GROUP BY DATE(created_at) ORDER BY date`
    ).all();
    return Response.json(result.results, { headers });
  }

  if (type === 'popular') {
    const result = await env.DB.prepare(
      `SELECT p.name, COUNT(d.id) as downloads 
       FROM downloads d JOIN patches p ON d.patch_id = p.id 
       GROUP BY d.patch_id ORDER BY downloads DESC LIMIT 10`
    ).all();
    return Response.json(result.results, { headers });
  }

  const users = await env.DB.prepare('SELECT COUNT(*) as count FROM users').first();
  const patches = await env.DB.prepare('SELECT COUNT(*) as count FROM patches').first();
  const downloads = await env.DB.prepare('SELECT COUNT(*) as count FROM downloads').first();
  const todayDownloads = await env.DB.prepare(
    "SELECT COUNT(*) as count FROM downloads WHERE DATE(created_at) = DATE('now')"
  ).first();

  return Response.json({
    totalUsers: users.count,
    totalPatches: patches.count,
    totalDownloads: downloads.count,
    todayDownloads: todayDownloads.count,
  }, { headers });
}

// ============================================================
// ADMIN ACTIVITY
// ============================================================

async function handleGetActivity(env, headers, url) {
  const limit = parseInt(url.searchParams.get('limit') || '50');
  const result = await env.DB.prepare(
    'SELECT * FROM activity_log ORDER BY created_at DESC LIMIT ?'
  ).bind(limit).all();
  return Response.json(result.results, { headers });
}

// ============================================================
// ADMIN CONFIG
// ============================================================

async function handleGetConfig(env, headers) {
  const result = await env.DB.prepare('SELECT * FROM config ORDER BY key').all();
  const config = {};
  result.results.forEach(r => { config[r.key] = r.value; });
  return Response.json(config, { headers });
}

async function handleUpdateConfig(request, env, headers) {
  const data = await request.json();
  const now = new Date().toISOString();

  for (const [key, value] of Object.entries(data)) {
    await env.DB.prepare(
      `INSERT INTO config (key, value, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET value = ?, updated_at = ?`
    ).bind(key, value, now, value, now).run();
  }

  await logActivity(env, 'config_updated', 'Configuration updated');
  return Response.json({ success: true }, { headers });
}
