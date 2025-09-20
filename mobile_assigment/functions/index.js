const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

/**
 * Creates exactly ONE invoice when a tracking doc enters
 * "Ready for Collection" (case-insensitive).
 *
 * Requires these fields on the tracking doc:
 *  - uid (Firebase Auth UID of the user)  ← used as invoice.userId
 *  - BookingID (or bookingID)            ← copied to invoice.bookingID
 *  - plateNumber                          ← copied to invoice.plateNumber
 *
 * Invoice fields created:
 *  - invoiceID: auto-id
 *  - userId: tracking.uid
 *  - bookingID: tracking.BookingID
 *  - plateNumber: tracking.plateNumber
 *  - amount: 120.0 (fixed)
 *  - status: 'pending'
 *  - date: serverTimestamp()
 *
 * Writes invoiceID back to the tracking doc (idempotent).
 */
exports.createInvoiceWhenReady = functions.firestore
  .document('Tracking/{TrackID}')
  .onWrite(async (change, context) => {
    const after = change.after.exists ? change.after.data() : null;
    if (!after) return; // deleted

    // Normalize status for comparison
    const status = String(after.status || '').toLowerCase();
    if (status !== 'ready for collection') return;

    // Already linked? Then we're done (idempotency)
    if (after.invoiceID) return;

    // Pull required fields (your keys)
    const userId = after.uid || after.UserID || null; // prefer 'uid'
    const bookingID = after.BookingID || after.bookingID || null;
    const plateNumber = after.plateNumber || null;

    if (!userId || !bookingID || !plateNumber) {
      console.warn(
        `[createInvoiceWhenReady] Missing required fields`,
        { trackId: context.params.trackId, userId, bookingID, plateNumber }
      );
      return;
    }

    const trackingRef = change.after.ref;
    const invoicesCol = db.collection('invoices');
    const FIXED_AMOUNT = 120.0;

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(trackingRef);
      if (!snap.exists) return;

      // Re-check in txn to avoid duplicates
      if (snap.data().invoiceID) return;

      const invoiceRef = invoicesCol.doc(); // auto-id
      const invoice = {
        invoiceID: invoiceRef.id,
        userId,
        bookingID,
        plateNumber,
        amount: FIXED_AMOUNT, // RM120 fixed
        status: 'pending',
        date: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Create the invoice
      tx.set(invoiceRef, invoice);

      // Back-link to tracking so we never create again
      tx.update(trackingRef, {
        invoiceID: invoiceRef.id,
        invoiceStatus: 'generated',
        invoiceCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    console.log(
      `[createInvoiceWhenReady] Invoice created for tracking ${context.params.trackId}`
    );
  });
