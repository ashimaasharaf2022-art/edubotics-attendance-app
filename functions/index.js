const { onSchedule } = require('firebase-functions/v2/scheduler');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const dateKey = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
// This backend job runs even when the app is closed. An office record remains
// pending until an admin accepts the request and chooses the actual checkout
// time. WFH records are completed automatically at the boundary.
exports.closeOpenAttendanceAtMidnight = onSchedule({ schedule: '59 23 * * *', timeZone: 'Asia/Kolkata' }, async () => {
  const now = new Date();
  const indiaNow = new Date(now.toLocaleString('en-US', { timeZone: 'Asia/Kolkata' }));
  const date = dateKey(indiaNow);
  const root = admin.database().ref();
  const attendance = await root.child('Attendance').once('value');
  const updates = {};
  attendance.forEach((employee) => {
    const record = employee.child(date).val();
    if (!record || record.status !== 'Checked In') return;
    const employeeId = employee.key;
    updates[`Attendance/${employeeId}/${date}/autoCheckedOutAt`] = now.toISOString();
    if (record.workFromHome === true) {
      updates[`Attendance/${employeeId}/${date}/punchOut`] = '11:59 PM';
      updates[`Attendance/${employeeId}/${date}/status`] = 'Checked Out';
      updates[`Attendance/${employeeId}/${date}/attendanceStatus`] = 'Full Day (WFH auto checkout)';
    } else {
      updates[`Attendance/${employeeId}/${date}/status`] = 'Auto Checkout Pending';
      updates[`Attendance/${employeeId}/${date}/attendanceStatus`] = 'Auto punch-out pending admin approval';
      updates[`PunchRequests/${employeeId}/${date}`] = { employeeId, date, type: 'auto_checkout', status: 'pending', punchIn: record.punchIn, suggestedPunchOut: '11:59 PM', message: 'Employee did not check out. Verify and select the actual checkout time.', createdAt: now.toISOString() };
    }
  });
  if (Object.keys(updates).length) await root.update(updates);
  logger.info(`Midnight attendance processing complete for ${date}`);
});
