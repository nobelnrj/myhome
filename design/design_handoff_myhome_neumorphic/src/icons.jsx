// icons.jsx — SF-Symbol-style icon set. Clean 24×24 line/fill glyphs.
// <Icon name="house" size={24} color="var(--accent)" weight={2} fill={false} />

function Icon({ name, size = 22, color = 'currentColor', weight = 1.8, fill = false, style = {} }) {
  const sw = weight;
  const common = { fill: 'none', stroke: color, strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const solid = { fill: color, stroke: 'none' };
  const P = {
    // ── tab bar ──
    'house': fill
      ? <path d="M4 11.5 12 4l8 7.5V20a1 1 0 0 1-1 1h-4v-6h-6v6H5a1 1 0 0 1-1-1z" {...solid}/>
      : <path d="M4 11.5 12 4l8 7.5V20a1 1 0 0 1-1 1h-4v-6h-6v6H5a1 1 0 0 1-1-1z" {...common}/>,
    'creditcard': <g><rect x="3" y="6" width="18" height="13" rx="2.5" {...(fill?solid:common)}/>{!fill && <path d="M3 10h18" {...common}/>}{fill && <rect x="6" y="14.5" width="5" height="2" rx="1" fill="var(--bg)"/>}</g>,
    'chart.pie': fill
      ? <g><path d="M12 3a9 9 0 1 0 9 9h-9z" {...solid}/><path d="M13 3.05V11h7.95A9 9 0 0 0 13 3.05z" fill={color} opacity="0.45"/></g>
      : <g><path d="M12 3a9 9 0 1 0 9 9" {...common}/><path d="M12 3v9h9a9 9 0 0 0-9-9z" {...common}/></g>,
    'chart.line': <g><path d="M4 4v15a1 1 0 0 0 1 1h15" {...common}/><path d="M7 14l3.5-4 3 2.5L20 6" {...common}/><path d="M16 6h4v4" {...common}/></g>,
    'note': <g><rect x="4" y="3.5" width="16" height="17" rx="2.5" {...(fill?solid:common)}/><path d="M8 8.5h8M8 12h8M8 15.5h5" stroke={fill?'var(--bg)':color} strokeWidth={sw} strokeLinecap="round"/></g>,
    'gear': <g><circle cx="12" cy="12" r="3.2" {...common}/><path d="M12 2.5v2.2M12 19.3v2.2M21.5 12h-2.2M4.7 12H2.5M18.7 5.3l-1.6 1.6M6.9 17.1l-1.6 1.6M18.7 18.7l-1.6-1.6M6.9 6.9 5.3 5.3" {...common}/></g>,
    // ── nav / controls ──
    'chevron.right': <path d="M9 5l7 7-7 7" {...common}/>,
    'chevron.left': <path d="M15 5l-7 7 7 7" {...common}/>,
    'chevron.down': <path d="M5 9l7 7 7-7" {...common}/>,
    'plus': <path d="M12 5v14M5 12h14" {...common}/>,
    'plus.circle.fill': <g><circle cx="12" cy="12" r="10" {...solid}/><path d="M12 8v8M8 12h8" stroke="var(--bg)" strokeWidth="2" strokeLinecap="round"/></g>,
    'xmark': <path d="M6 6l12 12M18 6 6 18" {...common}/>,
    'xmark.circle.fill': <g><circle cx="12" cy="12" r="10" fill="var(--label3)" stroke="none"/><path d="M9 9l6 6M15 9l-6 6" stroke="var(--bg)" strokeWidth="2" strokeLinecap="round"/></g>,
    'checkmark': <path d="M5 13l4 4 10-11" {...common}/>,
    'checkmark.circle.fill': <g><circle cx="12" cy="12" r="10" {...solid}/><path d="M7.5 12.5l3 3 6-6.5" stroke="var(--bg)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fill="none"/></g>,
    'magnifyingglass': <g><circle cx="11" cy="11" r="7" {...common}/><path d="M16.5 16.5 21 21" {...common}/></g>,
    'ellipsis': <g><circle cx="5" cy="12" r="1.6" {...solid}/><circle cx="12" cy="12" r="1.6" {...solid}/><circle cx="19" cy="12" r="1.6" {...solid}/></g>,
    'slider': <g><path d="M4 8h10M18 8h2M4 16h2M10 16h10" {...common}/><circle cx="16" cy="8" r="2.2" {...common}/><circle cx="8" cy="16" r="2.2" {...common}/></g>,
    'arrow.up.right': <path d="M7 17 17 7M9 7h8v8" {...common}/>,
    'arrow.down.left': <path d="M17 7 7 17M15 17H7V9" {...common}/>,
    'arrow.down': <path d="M12 5v14M6 13l6 6 6-6" {...common}/>,
    'arrow.up': <path d="M12 19V5M6 11l6-6 6 6" {...common}/>,
    'briefcase': <g><rect x="3" y="7.5" width="18" height="12.5" rx="2.5" {...(fill?solid:common)}/><path d="M8.5 7.5V6a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v1.5" {...common}/><path d="M3 12.5h18" stroke={fill?'var(--bg)':color} strokeWidth={sw} strokeLinecap="round"/></g>,
    'banknote': <g><rect x="2.5" y="6" width="19" height="12" rx="2.5" {...common}/><circle cx="12" cy="12" r="2.6" {...common}/><path d="M6 9.5h.01M18 14.5h.01" {...common}/></g>,
    'wallet': <g><rect x="3" y="6" width="18" height="13" rx="2.5" {...common}/><path d="M3 10h18M16.5 13.5h.01" {...common}/></g>,
    'calendar': <g><rect x="3.5" y="5" width="17" height="15.5" rx="2.5" {...common}/><path d="M3.5 9.5h17M8 3v4M16 3v4" {...common}/></g>,
    'bell': <g><path d="M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6z" {...(fill?solid:common)}/><path d="M10 19a2 2 0 0 0 4 0" {...common}/></g>,
    'faceid': <g><path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2" {...common}/><path d="M9 9.5v1.5M15 9.5v1.5M12 9.5v3.5M10.5 11.5h1.5M9.5 15s1 1.2 2.5 1.2S14.5 15 14.5 15" {...common}/></g>,
    'lock': <g><rect x="5" y="10.5" width="14" height="10" rx="2.5" {...(fill?solid:common)}/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" {...common}/></g>,
    'envelope': <g><rect x="3" y="5.5" width="18" height="13" rx="2.5" {...(fill?solid:common)}/><path d="M4 7l8 6 8-6" stroke={fill?'var(--bg)':color} strokeWidth={sw} fill="none" strokeLinecap="round" strokeLinejoin="round"/></g>,
    'sparkles': <g><path d="M12 4l1.4 4.1L17.5 9l-4.1 1.4L12 14.5l-1.4-4.1L6.5 9l4.1-.9z" {...solid}/><path d="M18 14l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7z" {...solid}/></g>,
    'trash': <g><path d="M5 7h14M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M7 7l1 13a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1l1-13" {...common}/></g>,
    'pencil': <path d="M5 19l1-4L16 5l3 3L9 18l-4 1z" {...common}/>,
    'delete.left': <g><path d="M8 5h11a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H8l-5-7 5-7z" {...common}/><path d="M11 9l5 5M16 9l-5 5" {...common}/></g>,
    'flag': <g><path d="M6 21V4M6 4h10l-2 3 2 3H6" {...(fill?solid:common)}/></g>,
    'circle': <circle cx="12" cy="12" r="8.5" {...common}/>,
    'largecircle.fill': <g><circle cx="12" cy="12" r="9" {...common}/><circle cx="12" cy="12" r="5" {...solid}/></g>,
    // ── categories ──
    'cart': <g><path d="M3 4h2l2.2 11.2a1.5 1.5 0 0 0 1.5 1.2h7.6a1.5 1.5 0 0 0 1.5-1.2L20 7H6" {...common}/><circle cx="9" cy="20" r="1.3" {...solid}/><circle cx="17" cy="20" r="1.3" {...solid}/></g>,
    'fork.knife': <g><path d="M7 3v8M5 3v4a2 2 0 0 0 4 0V3M7 11v10M16 3c-1.5 0-2.5 2-2.5 5 0 2 1 3 2 3.2V21M16 3v8.2" {...common}/></g>,
    'car': <g><path d="M4 16v2a1 1 0 0 0 1 1h1.5a1 1 0 0 0 1-1v-1M16.5 17v1a1 1 0 0 0 1 1H19a1 1 0 0 0 1-1v-2M4 16l1.2-5.5A2 2 0 0 1 7.2 9h9.6a2 2 0 0 1 2 1.5L20 16zM4 16h16" {...common}/><circle cx="7.5" cy="13" r="0.6" {...solid}/><circle cx="16.5" cy="13" r="0.6" {...solid}/></g>,
    'bolt': <path d="M13 3 5 13h6l-1 8 8-10h-6z" {...(fill?solid:common)}/>,
    'bag': <g><path d="M6 8h12l-1 12a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1z" {...common}/><path d="M9 9V7a3 3 0 0 1 6 0v2" {...common}/></g>,
    'cross': <path d="M10 4h4v6h6v4h-6v6h-4v-6H4v-4h6z" {...(fill?solid:common)}/>,
    'house.cat': fill ? <path d="M4 11.5 12 4l8 7.5V20a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z" {...solid}/> : <path d="M4 11.5 12 4l8 7.5V20a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z" {...common}/>,
    'repeat': <g><path d="M4 9a5 5 0 0 1 5-5h7l-2-2M20 15a5 5 0 0 1-5 5H8l2 2" {...common}/></g>,
    'tv': <g><rect x="3" y="5" width="18" height="12" rx="2" {...common}/><path d="M8 21h8M12 17v4" {...common}/></g>,
    'pills': <g><rect x="3" y="9" width="11" height="6.5" rx="3.25" transform="rotate(45 8.5 12)" {...common}/><circle cx="16.5" cy="16.5" r="4" {...common}/></g>,
    'fuelpump': <g><path d="M5 21V6a2 2 0 0 1 2-2h5a2 2 0 0 1 2 2v15M4 21h11" {...common}/><path d="M7 8h5" {...common}/><path d="M14 9l3 2.5V17a2 2 0 0 0 2 2 2 2 0 0 0 2-2v-6l-3-3" {...common}/></g>,
    'medicalbag': <g><rect x="3.5" y="7.5" width="17" height="12" rx="2.5" {...(fill?solid:common)}/><path d="M9 7.5V6a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 6v1.5" {...common}/><path d="M12 11v5M9.5 13.5h5" stroke={fill?'var(--bg)':color} strokeWidth={sw} strokeLinecap="round"/></g>,
    // ── checklist / notes ──
    'square': <rect x="4" y="4" width="16" height="16" rx="4.5" {...common}/>,
    'checkmark.square.fill': <g><rect x="3.5" y="3.5" width="17" height="17" rx="4.8" {...solid}/><path d="M7.5 12.5l3 3 6-6.5" stroke="var(--bg)" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" fill="none"/></g>,
    'textformat': <g><path d="M5 7h14M5 7V5.5M19 7V5.5M12 7v12M9.5 19h5" {...common}/></g>,
    'checklist': <g><path d="M10 7h9M10 12h9M10 17h9" {...common}/><path d="M3.5 6.5l1.2 1.2L7 5.5M3.5 16.5l1.2 1.2L7 15.5" {...common}/></g>,
    'minus': <path d="M5 12h14" {...common}/>,
    'bell.badge': <g><path d="M6 9a6 6 0 0 1 9.5-4.9" {...common}/><path d="M18 10.5V9" {...common}/><path d="M6 9c0 5-2 6-2 6h16s-2-1-2-6" {...common}/><path d="M10 19a2 2 0 0 0 4 0" {...common}/><circle cx="18.5" cy="5.5" r="3" fill="var(--red)" stroke="none"/></g>,
    'arrow.clockwise': <g><path d="M20 12a8 8 0 1 1-2.3-5.6" {...common}/><path d="M20 4v4h-4" {...common}/></g>,
    'envelope.open': <g><path d="M4 10l8-5 8 5v9a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 19z" {...common}/><path d="M4 10l8 5 8-5" {...common}/></g>,
    'clock': <g><circle cx="12" cy="12" r="8.5" {...common}/><path d="M12 7v5l3.5 2" {...common}/></g>,
  };
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" style={{ display: 'block', flexShrink: 0, ...style }}>
      {P[name] || P['circle']}
    </svg>
  );
}

Object.assign(window, { Icon });
