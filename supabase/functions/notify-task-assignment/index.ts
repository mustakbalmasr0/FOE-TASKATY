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
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      }
    })
  }

  try {
    // Verify JWT token from Authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      throw new Error('Invalid Authorization header format. Must be Bearer token')
    }

    const token = authHeader.split(' ')[1]
    if (!token) {
      throw new Error('No token provided')
    }

    // Initialize Supabase client with service role key
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    
    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Missing Supabase configuration')
    }

    const supabaseClient = createClient(supabaseUrl, supabaseKey)

    // Verify the JWT token
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token)
    
    if (authError || !user) {
      throw new Error('Invalid authorization token')
    }

    // Parse and validate request body
    let payload: NotificationPayload
    try {
      payload = await req.json()
    } catch (error) {
      console.error('JSON parsing error:', error)
      return new Response(
        JSON.stringify({ error: 'Invalid JSON in request body' }),
        { 
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    // Log incoming payload for debugging
    console.log('Incoming payload:', JSON.stringify(payload, null, 2))

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

    // First, let's check if the task exists with detailed logging
    console.log('Querying task with ID:', payload.task_id, 'type:', typeof payload.task_id)
    
    const { data: taskData, error: taskError } = await supabaseClient
      .from('tasks')
      .select('*')
      .eq('id', payload.task_id)
      .single()

    // Enhanced error logging
    if (taskError) {
      console.error('Task query error details:', {
        error: taskError,
        task_id: payload.task_id,
        task_id_type: typeof payload.task_id,
        error_code: taskError.code,
        error_message: taskError.message,
        error_details: taskError.details
      })
      
      // Check if it's a "not found" error specifically
      if (taskError.code === 'PGRST116') {
        // Let's try to get all tasks to see what exists
        const { data: allTasks, error: allTasksError } = await supabaseClient
          .from('tasks')
          .select('id, title')
          .limit(10)
        
        console.log('Available tasks:', allTasks)
        console.log('All tasks query error:', allTasksError)
        
        return new Response(
          JSON.stringify({ 
            error: 'Task not found', 
            task_id: payload.task_id,
            available_tasks: allTasks || [],
            details: taskError 
          }),
          { 
            status: 404,
            headers: { 'Content-Type': 'application/json' }
          }
        )
      }
      
      return new Response(
        JSON.stringify({ 
          error: 'Database error while fetching task', 
          task_id: payload.task_id,
          details: taskError 
        }),
        { 
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    if (!taskData) {
      console.error('Task not found - no data returned for task_id:', payload.task_id)
      
      // Let's check what tasks exist
      const { data: allTasks } = await supabaseClient
        .from('tasks')
        .select('id, title')
        .limit(10)
      
      console.log('Available tasks:', allTasks)
      
      return new Response(
        JSON.stringify({ 
          error: 'Task not found', 
          task_id: payload.task_id,
          available_tasks: allTasks || []
        }),
        { 
          status: 404,
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

    // Get user's FCM token
    console.log('Fetching user profile for:', payload.user_id)
    const { data: userProfile, error: profileError } = await supabaseClient
      .from('profiles')
      .select('fcm_token, full_name')
      .eq('id', payload.user_id)
      .single()

    if (profileError) {
      console.error('Profile query error:', profileError)
      return new Response(
        JSON.stringify({ 
          error: 'User profile not found', 
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
      console.error('No FCM token found for user:', payload.user_id)
      return new Response(
        JSON.stringify({ 
          error: 'No FCM token found for user', 
          user_id: payload.user_id,
          profile: userProfile
        }),
        { 
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    console.log('User profile found:', { id: userProfile.id, has_fcm_token: !!userProfile.fcm_token })

    // Get assigned by user name
    const { data: assignedByUser } = await supabaseClient
      .from('profiles')
      .select('full_name')
      .eq('id', payload.assigned_by_id)
      .single()

    const assignedByName = assignedByUser?.full_name || 'المدير'
    const taskTitle = payload.task_title || taskData.title || taskData.name || 'مهمة جديدة'
    const notificationType = payload.type || 'task_assigned'

    console.log('Notification details:', {
      taskTitle,
      assignedByName,
      notificationType
    })

    // Get Firebase project ID and service account key
    const firebaseProjectId = Deno.env.get('FIREBASE_PROJECT_ID')
    const firebaseServiceAccountKey = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_KEY')
    
    if (!firebaseProjectId) {
      console.warn('FIREBASE_PROJECT_ID not configured, skipping FCM notification')
      
      // Log notification in database instead
      try {
        await supabaseClient.from('notifications').insert({
          user_id: payload.user_id,
          task_id: payload.task_id.toString(),
          title: 'مهمة جديدة مُسندة إليك',
          body: `تم تكليفك بمهمة: ${taskTitle} من قِبل ${assignedByName}`,
          type: notificationType,
          sent_at: new Date().toISOString(),
          status: 'logged_only'
        })
      } catch (error) {
        console.warn('Could not log notification to database:', error)
      }

      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'Task assigned successfully (notification logged only)',
          task_id: payload.task_id,
          user_id: payload.user_id,
          task_title: taskTitle,
          note: 'FCM not configured'
        }),
        { 
          status: 200,
          headers: { 
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
          }
        }
      )
    }

    if (!firebaseServiceAccountKey) {
      console.warn('FIREBASE_SERVICE_ACCOUNT_KEY not configured, skipping FCM notification')
      
      // Log notification in database instead
      try {
        await supabaseClient.from('notifications').insert({
          user_id: payload.user_id,
          task_id: payload.task_id.toString(),
          title: 'مهمة جديدة مُسندة إليك',
          body: `تم تكليفك بمهمة: ${taskTitle} من قِبل ${assignedByName}`,
          type: notificationType,
          sent_at: new Date().toISOString(),
          status: 'logged_only'
        })
      } catch (error) {
        console.warn('Could not log notification to database:', error)
      }

      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'Task assigned successfully (notification logged only)',
          task_id: payload.task_id,
          user_id: payload.user_id,
          task_title: taskTitle,
          note: 'FCM service account not configured'
        }),
        { 
          status: 200,
          headers: { 
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
          }
        }
      )
    }

    // Generate OAuth2 access token for Firebase v1 API
    let accessToken: string
    try {
      const serviceAccount = JSON.parse(firebaseServiceAccountKey)
      
      // Create JWT for OAuth2 flow
      const now = Math.floor(Date.now() / 1000)
      const jwtHeader = {
        alg: 'RS256',
        typ: 'JWT'
      }
      
      const jwtPayload = {
        iss: serviceAccount.client_email,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: 'https://oauth2.googleapis.com/token',
        exp: now + 3600,
        iat: now
      }

      // Create the JWT
      const jwt = await createJWT(jwtHeader, jwtPayload, serviceAccount.private_key)
      
      // Exchange JWT for access token
      const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: new URLSearchParams({
          grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          assertion: jwt
        })
      })

      if (!tokenResponse.ok) {
        const errorText = await tokenResponse.text()
        console.error('Token response error:', errorText)
        throw new Error(`Failed to get Firebase access token: ${tokenResponse.status}`)
      }

      const tokenData = await tokenResponse.json()
      accessToken = tokenData.access_token
      
      console.log('Successfully obtained Firebase access token')
    } catch (error) {
      console.error('Failed to authenticate with Firebase:', error)
      
      // Log notification in database instead of failing
      try {
        await supabaseClient.from('notifications').insert({
          user_id: payload.user_id,
          task_id: payload.task_id.toString(),
          title: 'مهمة جديدة مُسندة إليك',
          body: `تم تكليفك بمهمة: ${taskTitle} من قِبل ${assignedByName}`,
          type: notificationType,
          sent_at: new Date().toISOString(),
          status: 'auth_failed'
        })
      } catch (dbError) {
        console.warn('Could not log notification to database:', dbError)
      }

      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'Task assigned successfully (notification auth failed)',
          task_id: payload.task_id,
          user_id: payload.user_id,
          task_title: taskTitle,
          note: 'Firebase authentication failed'
        }),
        { 
          status: 200,
          headers: { 
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
          }
        }
      )
    }

    // Prepare FCM payload using v1 API format
    const fcmPayload = {
      message: {
        token: userProfile.fcm_token,
        notification: {
          title: 'مهمة جديدة مُسندة إليك',
          body: `تم تكليفك بمهمة: ${taskTitle} من قِبل ${assignedByName}`,
        },
        data: {
          type: notificationType,
          task_id: payload.task_id.toString(),
          task_title: taskTitle,
          assigned_by: assignedByName,
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

    console.log('Sending FCM notification with payload:', JSON.stringify(fcmPayload, null, 2))

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