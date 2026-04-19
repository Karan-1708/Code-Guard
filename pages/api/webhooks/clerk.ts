import { Webhook } from 'svix';
import { buffer } from 'micro';
import { NextApiRequest, NextApiResponse } from 'next';
import { createClerkClient } from '@clerk/nextjs/server';

export const config = {
  api: {
    bodyParser: false,
  },
};

const client = createClerkClient({ secretKey: process.env.CLERK_SECRET_KEY });

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== 'POST') {
    return res.status(405).json({ message: 'Method not allowed' });
  }

  const WEBHOOK_SECRET = process.env.CLERK_WEBHOOK_SECRET;

  if (!WEBHOOK_SECRET) {
    throw new Error('Please add CLERK_WEBHOOK_SECRET from Clerk Dashboard to .env or .env.local');
  }

  // Get the headers
  const svix_id = req.headers["svix-id"] as string;
  const svix_timestamp = req.headers["svix-timestamp"] as string;
  const svix_signature = req.headers["svix-signature"] as string;

  // If there are no headers, error out
  if (!svix_id || !svix_timestamp || !svix_signature) {
    return res.status(400).json({ error: 'Error occured -- no svix headers' });
  }

  // Get the body
  const body = (await buffer(req)).toString();

  // Create a new Svix instance with your secret.
  const wh = new Webhook(WEBHOOK_SECRET);

  let evt: any;

  // Verify the payload with the headers
  try {
    evt = wh.verify(body, {
      "svix-id": svix_id,
      "svix-timestamp": svix_timestamp,
      "svix-signature": svix_signature,
    });
  } catch (err) {
    console.error('Error verifying webhook:', err);
    return res.status(400).json({ Error: err });
  }

  // Handle the webhook
  const eventType = evt.type;
  console.log('Received Clerk Webhook:', eventType, evt.data);

  if (eventType === 'subscription.created' || eventType === 'subscription.updated') {
    const { payer, status } = evt.data;
    const userId = payer?.user_id;

    if (!userId) {
      console.error(`No payer.user_id found in ${eventType} payload`, evt.data);
      return res.status(400).json({ error: 'No payer.user_id' });
    }

    // Only grant premium if the subscription is active
    const isPremium = status === 'active';
    console.log(`Setting premium status to ${isPremium} for user ${userId}...`);

    try {
      await client.users.updateUserMetadata(userId, {
        publicMetadata: {
          plan: isPremium ? "paid_subscription" : "free_user"
        }
      });
      console.log('User updated successfully.');
    } catch (err) {
      console.error('Error updating user metadata:', err);
      return res.status(500).json({ error: 'Error updating user' });
    }
  }

  return res.status(200).json({ response: 'Success' });
}
