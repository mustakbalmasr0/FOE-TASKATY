// supabase/functions/notify-task-assignment/index.ts
// Updated to use Firebase FCM v1 API format

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm"

interface NotificationPayload {
  task_id: number
  user_id: string
  assigned_by_id: string
  type?: string
  task_title?: string
}

interface TaskData {
  id: number
  title?: string
  name?: string
  assigned_user_id?: string
  assigned_by_id?: string
  due_date?: string
  priority?: string
  description?: string
  created_by?: string
}

interface UserProfile {
  id: string
  full_name?: string
  fcm_token?: string
}

// Validate payload
const validatePayload = (payload: any): payload is NotificationPayload => {
  if (!payload) {
    throw new Error('Request body is required')
  }
  
  // Convert task_id to number if it's a string
  if (payload.task_id) {
    if (typeof payload.task_id === 'string') {
      const parsed = parseInt(payload.task_id, 10)
      if (isNaN(parsed)) {
        throw new Error('task_id must be a valid number')
      }
      payload.task_id = parsed
    } else if (typeof payload.task_id !== 'number') {
      throw new Error('task_id must be a number')
    }
  } else {
    throw new Error('task_id is required')
  }
  
  if (!payload.user_id || typeof payload.user_id !== 'string') {
    throw new Error('user_id is required and must be a string')
  }
  
  if (!payload.assigned_by_id || typeof payload.assigned_by_id !== 'string') {
    throw new Error('assigned_by_id is required and must be a string')
  }
  
  return true
}

serve(async (req) => {
  // Add request logging
  console.log('=== Edge Function notify-task-assignment called ===');
  console.log('Request method:', req.method);
  console.log('Request headers:', Object.fromEntries(req.headers.entries()));
  
  // Handle CORS
  if (req.method === 'OPTIONS') {
    console.log('Handling CORS preflight request');
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      }
    })
  }

  try {
    console.log('Processing POST request...');
    
    // Verify JWT token from Authorization header
    const authHeader = req.headers.get('Authorization')
    console.log('Authorization header present:', !!authHeader);
    
    if (!authHeader?.startsWith('Bearer ')) {
      console.error('Invalid Authorization header format');
      throw new Error('Invalid Authorization header format. Must be Bearer token')
    }

    const token = authHeader.split(' ')[1]
    if (!token) {
      console.error('No token provided in Authorization header');
      throw new Error('No token provided')
    }

    console.log('Token extracted successfully');

    // Initialize Supabase client with service role key
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    
    console.log('Supabase URL configured:', !!supabaseUrl);
    console.log('Supabase Service Role Key configured:', !!supabaseKey);
    
    if (!supabaseUrl || !supabaseKey) {
      console.error('Missing Supabase configuration');
      throw new Error('Missing Supabase configuration')
    }

    const supabaseClient = createClient(supabaseUrl, supabaseKey)
    console.log('Supabase client initialized');

    // Verify the JWT token
    console.log('Verifying JWT token...');
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token)
    
    if (authError || !user) {
      console.error('JWT verification failed:', authError);
      throw new Error('Invalid authorization token')
    }

    console.log('JWT verified successfully for user:', user.id);

    // Parse and validate request body
    let payload: NotificationPayload
    let rawBody: string
    try {
      rawBody = await req.text()
      console.log('Raw request body:', rawBody);
      payload = JSON.parse(rawBody)
    } catch (error) {
      console.error('JSON parsing error:', error)
      return new Response(
        JSON.stringify({ error: 'Invalid JSON in request body', raw_body: rawBody }),
        { 
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    // Log incoming payload for debugging
    console.log('Parsed payload:', JSON.stringify(payload, null, 2))

    // Validate payload
    try {
      validatePayload(payload)
    } catch (error) {
      console.error('Payload validation error:', error.message)
      return new Response(
        JSON.stringify({ error: error.message }),
        { 
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    console.log('Processing notification for task_id:', payload.task_id, 'user_id:', payload.user_id)
    console.log('Notification will be sent TO user:', payload.user_id)
    console.log('Notification is FROM user (admin):', payload.assigned_by_id)

    // Verify the user_id and assigned_by_id are different
    if (payload.user_id === payload.assigned_by_id) {
      console.error('ERROR: user_id and assigned_by_id are the same! This would send notification to admin.')
      console.error('user_id (should be assigned user):', payload.user_id)
      console.error('assigned_by_id (should be admin):', payload.assigned_by_id)
      
      return new Response(
        JSON.stringify({ 
          error: 'Invalid assignment: Cannot assign task to yourself',
          user_id: payload.user_id,
          assigned_by_id: payload.assigned_by_id
        }),
        { 
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    console.log('Task found:', taskData)

    // Check if task_assignments table exists and create the assignment record
    try {
      const { data: assignmentData, error: assignmentError } = await supabaseClient
        .from('task_assignments')
        .insert({
          task_id: payload.task_id,
          user_id: payload.user_id,
          assigned_at: new Date().toISOString()
        })
        .select()
        .single()

      if (assignmentError) {
        console.error('Assignment creation error:', assignmentError)
        // Don't fail the notification if assignment logging fails
        console.warn('Could not log task assignment, but continuing with notification')
      } else {
        console.log('Task assignment logged:', assignmentData)
      }
    } catch (error) {
      console.warn('Task assignment logging failed:', error)
      // Continue with notification even if assignment logging fails
    }

    // Get user's FCM token (THIS IS THE ASSIGNED USER, NOT THE ADMIN)
    console.log('Fetching FCM token for ASSIGNED USER:', payload.user_id)
    const { data: userProfile, error: profileError } = await supabaseClient
      .from('profiles')
      .select('fcm_token, name, full_name')
      .eq('id', payload.user_id)
      .single()

    if (profileError) {
      console.error('Profile query error for assigned user:', profileError)
      return new Response(
        JSON.stringify({ 
          error: 'Assigned user profile not found', 
          user_id: payload.user_id,
          details: profileError 
        }),
        { 
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    if (!userProfile?.fcm_token) {
      console.error('No FCM token found for assigned user:', payload.user_id)
      console.log('User profile:', userProfile)
      return new Response(
        JSON.stringify({ 
          error: 'No FCM token found for assigned user', 
          user_id: payload.user_id,
          profile: userProfile
        }),
        { 
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    console.log('Assigned user profile found:', { 
      id: payload.user_id,
      name: userProfile.name || userProfile.full_name || 'Unknown',
      has_fcm_token: !!userProfile.fcm_token 
    })

    // Get assigned by user name (THIS IS THE ADMIN WHO CREATED THE TASK)
    console.log('Fetching admin name for assigned_by_id:', payload.assigned_by_id)
    const { data: assignedByUser } = await supabaseClient
      .from('profiles')
      .select('name, full_name')
      .eq('id', payload.assigned_by_id)
      .single()

    const assignedByName = assignedByUser?.name || assignedByUser?.full_name || 'المدير'
    const assignedUserName = userProfile.name || userProfile.full_name || 'المستخدم'
    
    console.log('Assignment details:')
    console.log('  - Task will be assigned TO:', assignedUserName, '(ID:', payload.user_id, ')')
    console.log('  - Task is assigned BY:', assignedByName, '(ID:', payload.assigned_by_id, ')')
    console.log('  - FCM token belongs to assigned user:', payload.user_id)

    // Prepare FCM payload using v1 API format
    const fcmPayload = {
      message: {
        token: userProfile.fcm_token, // This token belongs to the ASSIGNED USER
        notification: {
          title: 'مهمة جديدة مُسندة إليك',
          body: `تم تكليفك بمهمة: ${taskTitle} من قِبل ${assignedByName}`,
        },
        data: {
          type: notificationType,
          task_id: payload.task_id.toString(),
          task_title: taskTitle,
          assigned_by: assignedByName,
          assigned_to: assignedUserName,
          due_date: taskData.due_date || '',
          priority: taskData.priority || 'medium',
          click_action: 'FLUTTER_NOTIFICATION_CLICK'
        },
        android: {
          priority: 'high',
          notification: {
            channel_id: 'task_notifications',
            sound: 'default'
          }
        },
        apns: {
          headers: {
            'apns-priority': '10'
          },
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
              'content-available': 1
            }
          }
        }
      }
    }

    console.log('About to send FCM notification:')
    console.log('  - TO user:', assignedUserName, '(FCM token from user_id:', payload.user_id, ')')
    console.log('  - FROM user:', assignedByName, '(assigned_by_id:', payload.assigned_by_id, ')')
    console.log('FCM payload:', JSON.stringify(fcmPayload, null, 2))

    // Send FCM notification using v1 API
    const fcmResponse = await fetch(
      `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(fcmPayload)
      }
    )

    const fcmResult = await fcmResponse.json()

    if (!fcmResponse.ok) {
      console.error('FCM Error:', fcmResult)
      return new Response(
        JSON.stringify({ 
          error: 'Failed to send notification', 
          fcm_status: fcmResponse.status,
          details: fcmResult 
        }),
        { 
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    console.log('FCM notification sent successfully:', fcmResult)

    // Log notification in database (optional, don't fail if this fails)
    try {
      await supabaseClient.from('notifications').insert({
        user_id: payload.user_id,
        task_id: payload.task_id.toString(),
        title: 'مهمة جديدة مُسندة إليك',
        body: `تم تكليفك بمهمة: ${taskTitle} من قِبل ${assignedByName}`,
        type: notificationType,
        sent_at: new Date().toISOString()
      })
    } catch (error) {
      console.warn('Could not log notification to database:', error)
    }

    console.log('Notification sent successfully for task:', payload.task_id)

    return new Response(
      JSON.stringify({ 
        success: true, 
        message: 'Notification sent successfully',
        task_id: payload.task_id,
        user_id: payload.user_id,
        task_title: taskTitle,
        fcm_message_id: fcmResult.name
      }),
      { 
        status: 200,
        headers: { 
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        }
      }
    )

  } catch (error) {
    console.error('Error in notify-task-assignment function:', error)
    console.error('Error stack:', error.stack)
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error', 
        message: error.message,
        timestamp: new Date().toISOString()
      }),
      { 
        status: 500,
        headers: { 
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        }
      }
    )
  }
})

// JWT creation function for Firebase authentication
async function createJWT(header: any, payload: any, privateKey: string): Promise<string> {
  // Clean the private key
  const cleanPrivateKey = privateKey
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  
  // Convert base64 to ArrayBuffer
  const keyData = Uint8Array.from(atob(cleanPrivateKey), c => c.charCodeAt(0))
  
  // Import the private key
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    keyData,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256'
    },
    false,
    ['sign']
  )
  
  // Create the unsigned token
  const headerB64 = base64UrlEncode(JSON.stringify(header))
  const payloadB64 = base64UrlEncode(JSON.stringify(payload))
  const unsignedToken = `${headerB64}.${payloadB64}`
  
  // Sign the token
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(unsignedToken)
  )
  
  const signatureB64 = base64UrlEncode(String.fromCharCode(...new Uint8Array(signature)))
  
  return `${unsignedToken}.${signatureB64}`
}

// Base64 URL encode helper
function base64UrlEncode(str: string): string {
  return btoa(str)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')
}