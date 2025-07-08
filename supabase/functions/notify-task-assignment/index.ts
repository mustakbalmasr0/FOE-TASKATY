// supabase/functions/notify-task-assignment/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm"


interface NotificationPayload {
  task_id: number
  user_id: string
  assigned_by_id: string
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
    // Initialize Supabase client
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Parse request body
    const payload: NotificationPayload = await req.json()

    // Get task details and assigned user info
    const { data: taskData, error: taskError } = await supabaseClient
      .from('tasks')
      .select(`
        *,
        assigned_user:profiles!tasks_assigned_user_id_fkey(id, full_name),
        assigned_by:profiles!tasks_assigned_by_id_fkey(id, full_name)
      `)
      .eq('id', payload.task_id)
      .single()

    if (taskError || !taskData) {
      console.error('Task not found:', payload.task_id)
      return new Response(
        JSON.stringify({ error: 'Task not found' }),
        { 
          status: 404,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    // Get user's FCM token
    const { data: userToken, error: tokenError } = await supabaseClient
      .from('user_tokens')
      .select('fcm_token')
      .eq('user_id', payload.user_id)
      .single()

    if (tokenError || !userToken?.fcm_token) {
      console.error('No FCM token found for user:', payload.user_id)
      return new Response(
        JSON.stringify({ error: 'No FCM token found for user' }),
        { 
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    // Get assigned by user name
    const { data: assignedByUser, error: assignedByError } = await supabaseClient
      .from('profiles')
      .select('full_name')
      .eq('id', payload.assigned_by_id)
      .single()

    const assignedByName = assignedByUser?.full_name || 'المدير'

    // Prepare FCM notification
    const fcmPayload = {
      to: userToken.fcm_token,
      notification: {
        title: 'مهمة جديدة مُسندة إليك',
        body: `تم تكليفك بمهمة: ${taskData.title || taskData.name} من قِبل ${assignedByName}`,
        icon: 'ic_notification',
        sound: 'default'
      },
      data: {
        task_id: payload.task_id.toString(),
        task_title: taskData.title || taskData.name || '',
        assigned_by: assignedByName,
        due_date: taskData.due_date || '',
        priority: taskData.priority || 'medium',
        click_action: 'FLUTTER_NOTIFICATION_CLICK'
      }
    }

    // Send FCM notification
    const fcmResponse = await fetch('https://fcm.googleapis.com/fcm/send', {
      method: 'POST',
      headers: {
        'Authorization': `key=${Deno.env.get('FCM_SERVER_KEY')}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(fcmPayload)
    })

    const fcmResult = await fcmResponse.json()

    if (!fcmResponse.ok) {
      console.error('FCM Error:', fcmResult)
      return new Response(
        JSON.stringify({ error: 'Failed to send notification', details: fcmResult }),
        { 
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    // Log notification in database (optional)
    await supabaseClient.from('notifications').insert({
      user_id: payload.user_id,
      task_id: payload.task_id.toString(),
      title: 'مهمة جديدة مُسندة إليك',
      body: `تم تكليفك بمهمة: ${taskData.title || taskData.name} من قِبل ${assignedByName}`,
      type: 'task_assignment',
      sent_at: new Date().toISOString()
    })

    return new Response(
      JSON.stringify({ 
        success: true, 
        message: 'Notification sent successfully',
        fcm_message_id: fcmResult.message_id 
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
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: error.message }),
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