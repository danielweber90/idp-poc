import { useEffect, useState } from 'react'

interface Item {
  id: number
  title: string
}

export default function App() {
  const [items, setItems] = useState<Item[]>([])
  const [title, setTitle] = useState('')
  const [status, setStatus] = useState<'idle' | 'loading' | 'error'>('idle')

  const basePath = import.meta.env.BASE_URL  // injected by Vite from VITE_BASE_PATH

  useEffect(() => {
    fetch(`${basePath}api/items`)
      .then(r => r.json())
      .then(setItems)
      .catch(() => setStatus('error'))
  }, [basePath])

  const addItem = async () => {
    if (!title.trim()) return
    setStatus('loading')
    const res = await fetch(`${basePath}api/items`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title }),
    })
    if (res.ok) {
      const item = await res.json()
      setItems(prev => [...prev, item])
      setTitle('')
    }
    setStatus('idle')
  }

  return (
    <div style={{ maxWidth: 600, margin: '2rem auto', fontFamily: 'sans-serif' }}>
      <h1>My Webapp</h1>
      <div style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
        <input
          value={title}
          onChange={e => setTitle(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && addItem()}
          placeholder="New item…"
          style={{ flex: 1, padding: 8 }}
        />
        <button onClick={addItem} disabled={status === 'loading'}>Add</button>
      </div>
      {status === 'error' && <p style={{ color: 'red' }}>Could not reach backend.</p>}
      <ul>
        {items.map(item => <li key={item.id}>{item.title}</li>)}
      </ul>
    </div>
  )
}
