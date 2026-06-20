// settings.jsx — security, Gmail import, sync window, fixed prefs.
function SettingsScreen({ ctx }) {
  const { faceID, setFaceID, gmailOn, setGmailOn, syncDays, setSyncDays, lastSynced, onSyncNow, syncing, nav, openNotifications } = ctx;
  return (
    <Screen title="Settings">
      {/* profile */}
      <div style={{ padding: '0 16px 22px' }}>
        <div style={{ background: 'var(--glass-tint)', backdropFilter: 'var(--glass-blur)', WebkitBackdropFilter: 'var(--glass-blur)', border: 'var(--glass-border)', borderRadius: 'var(--card-radius)', boxShadow: 'var(--card-shadow)', padding: 16, display: 'flex', alignItems: 'center', gap: 14 }}>
          <div style={{ width: 56, height: 56, borderRadius: '50%', background: 'linear-gradient(135deg, var(--accent), color-mix(in srgb, var(--accent) 55%, #fff))',
            display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: SF, fontSize: 22, fontWeight: 600, color: '#fff' }}>{PROFILE.initials}</div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontFamily: SF, fontSize: 20, fontWeight: 600, color: 'var(--label)', letterSpacing: -0.5 }}>{PROFILE.name}</div>
            <div style={{ fontFamily: SF, fontSize: 14, color: 'var(--label2)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{PROFILE.email}</div>
          </div>
        </div>
      </div>

      {/* security */}
      <GroupedList header="Security">
        <Row iconNode={<IconTile icon="faceid" color="var(--green)" size={29} />} title="Face ID Lock" accessory={<Toggle value={faceID} onChange={setFaceID} />} />
        <Row iconNode={<IconTile icon="lock" color="#8E8E93" size={29} />} title="Change passcode" accessory="chevron" />
      </GroupedList>

      {/* notifications route */}
      <GroupedList footer="Push notifications aren’t enabled. Reminder and budget alerts are shown inside the app.">
        <Row iconNode={<IconTile icon="bell" color="var(--red)" size={29} />} title="Notifications" onClick={openNotifications} accessory="chevron" />
      </GroupedList>

      {/* Gmail import */}
      <GroupedList header="Gmail"
        footer="MyHome reads receipts and bank alerts from your inbox to detect expenses. Detected charges land in your Review inbox before being added.">
        <Row iconNode={<IconTile icon="envelope" color="#EA4335" size={29} />} title="Gmail" subtitle={gmailOn ? PROFILE.email : 'Not connected'}
          accessory={<Toggle value={gmailOn} onChange={setGmailOn} />} />
        {gmailOn && <Row iconNode={<Icon name="clock" size={22} color="var(--label2)" />} title="Last synced" value={syncing ? 'Syncing…' : lastSynced} accessory="none" />}
        {gmailOn && <Row iconNode={<Icon name="arrow.clockwise" size={22} color="var(--accent)" />} title="Sync now" titleColor="var(--accent)" onClick={onSyncNow} accessory="none" />}
        {gmailOn && <Row iconNode={<Icon name="envelope.open" size={22} color="var(--orange)" />} title="Reconnect Gmail" titleColor="var(--orange)" accessory="none" />}
        {gmailOn && <Row accessory="none" leftInset={16} title="Sign out" titleColor="var(--red)" />}
      </GroupedList>

      {/* sync window */}
      {gmailOn && (
        <GroupedList header="Sync window" footer={`On each sync, MyHome scans the last ${syncDays} days of email. A longer window catches older receipts but takes more time.`}>
          <Row iconNode={<Icon name="calendar" size={22} color="var(--accent)" />} title="Days of mail to scan"
            value={<span style={{ display: 'inline-flex', alignItems: 'center', gap: 12 }}>
              <span style={{ fontFamily: SF, fontSize: 17, fontWeight: 600, color: 'var(--label)', minWidth: 64, textAlign: 'right' }}>{syncDays} days</span>
              <Stepper onDec={() => setSyncDays(d => Math.max(30, d - 30))} onInc={() => setSyncDays(d => Math.min(365, d + 30))} />
            </span>} accessory="none" />
        </GroupedList>
      )}

      {/* data */}
      <GroupedList header="Data">
        <Row iconNode={<IconTile icon="chart.pie" color="var(--accent)" size={29} />} title="Manage budgets" onClick={() => nav('budgets')} accessory="chevron" />
        <Row iconNode={<IconTile icon="creditcard" color="#8E8E93" size={29} />} title="Accounts" value={`${ACCOUNTS.length}`} accessory="chevron" />
      </GroupedList>

      {/* fixed prefs */}
      <GroupedList header="Preferences" footer="Currency and budget period are fixed in this version.">
        <Row iconNode={<IconTile icon="creditcard" color="var(--green)" size={29} />} title="Currency" value="₹ INR" accessory="none" />
        <Row iconNode={<IconTile icon="calendar" color="var(--orange)" size={29} />} title="Budget period" value="Monthly" accessory="none" />
      </GroupedList>

      <GroupedList footer="MyHome v7.0 · Phase 7">
        <Row iconNode={<IconTile icon="house" color="var(--accent)" size={29} />} title="About MyHome" accessory="chevron" />
      </GroupedList>
    </Screen>
  );
}
Object.assign(window, { SettingsScreen });
