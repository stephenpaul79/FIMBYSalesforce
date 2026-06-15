/**
 * Push Notification Hook for FIMBY Mobile App
 *
 * Handles:
 * - Permission requests
 * - Token registration with backend
 * - Notification listeners
 * - Deep linking from notifications
 */

import { useState, useEffect, useRef, useCallback } from "react";
import { Platform, Alert } from "react-native";
import * as Notifications from "expo-notifications";
import * as Device from "expo-device";
import Constants from "expo-constants";
import { log } from "../lib/log";

// Backend URL
const BACKEND_BASE_URL = "https://fimby-auth-bridge.vercel.app";
const PUSH_TOKEN_URL = `${BACKEND_BASE_URL}/api/push-token`;

// Configure how notifications appear when app is foregrounded
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
});

export type NotificationData = {
  notification_type?: string;
  [key: string]: any;
};

export type PushNotificationState = {
  expoPushToken: string | null;
  notification: Notifications.Notification | null;
  error: string | null;
};

type UsePushNotificationsOptions = {
  onNotificationReceived?: (notification: Notifications.Notification) => void;
  onNotificationTapped?: (data: NotificationData) => void;
};

/**
 * Hook to manage push notifications
 */
export function usePushNotifications(options: UsePushNotificationsOptions = {}) {
  const [expoPushToken, setExpoPushToken] = useState<string | null>(null);
  const [notification, setNotification] = useState<Notifications.Notification | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [permissionStatus, setPermissionStatus] = useState<string | null>(null);

  const notificationListener = useRef<Notifications.Subscription | undefined>(undefined);
  const responseListener = useRef<Notifications.Subscription | undefined>(undefined);

  const { onNotificationReceived, onNotificationTapped } = options;

  /**
   * Request permissions and get Expo push token.
   *
   * Pass { prompt: false } to register only when permission is ALREADY granted
   * — this never shows the OS permission dialog. Used on the login/app-open path
   * so the system prompt can't fire mid-navigation during the Salesforce
   * frontdoor handoff (which briefly backgrounds the app and ejects the in-flight
   * WebView load). The first-time prompt is deferred to a stable moment instead.
   */
  const registerForPushNotifications = useCallback(
    async (options: { prompt?: boolean } = {}): Promise<string | null> => {
    const { prompt = true } = options;
    // Push notifications only work on physical devices
    if (!Device.isDevice) {
      log("[PUSH] Push notifications require a physical device");
      setError("Push notifications require a physical device");
      return null;
    }

    try {
      // Check existing permissions
      const { status: existingStatus } = await Notifications.getPermissionsAsync();
      let finalStatus = existingStatus;

      // Request if not granted (unless caller asked us not to prompt)
      if (existingStatus !== "granted") {
        if (!prompt) {
          log("[PUSH] Permission not granted and prompt suppressed; skipping");
          setPermissionStatus(existingStatus);
          return null;
        }
        const { status } = await Notifications.requestPermissionsAsync();
        finalStatus = status;
      }

      setPermissionStatus(finalStatus);

      if (finalStatus !== "granted") {
        log("[PUSH] Permission denied");
        setError("Push notification permission denied");
        return null;
      }

      // Get Expo push token
      const projectId = Constants.expoConfig?.extra?.eas?.projectId;

      const tokenData = await Notifications.getExpoPushTokenAsync({
        projectId,
      });

      const token = tokenData.data;
      log("[PUSH] Expo push token acquired");
      setExpoPushToken(token);
      setError(null);

      // Set up Android notification channel
      if (Platform.OS === "android") {
        await Notifications.setNotificationChannelAsync("default", {
          name: "Default",
          importance: Notifications.AndroidImportance.MAX,
          vibrationPattern: [0, 250, 250, 250],
          lightColor: "#3A7D8C",
        });

        // Additional channels for different notification types
        await Notifications.setNotificationChannelAsync("messages", {
          name: "Messages",
          description: "Direct message notifications",
          importance: Notifications.AndroidImportance.HIGH,
          vibrationPattern: [0, 250, 250, 250],
          lightColor: "#3A7D8C",
        });

        await Notifications.setNotificationChannelAsync("activity", {
          name: "Activity",
          description: "Marketplace, library, and story notifications",
          importance: Notifications.AndroidImportance.DEFAULT,
          lightColor: "#3A7D8C",
        });
      }

      return token;
    } catch (e: any) {
      log("[PUSH] Error registering for push notifications:", e?.message);
      setError(e?.message || "Failed to register for push notifications");
      return null;
    }
  }, []);

  /**
   * Send push token to backend
   */
  const registerTokenWithBackend = useCallback(
    async (accessToken: string, pushToken?: string): Promise<boolean> => {
      const token = pushToken || expoPushToken;

      if (!token) {
        log("[PUSH] No push token to register");
        return false;
      }

      try {
        log("[PUSH] Registering token with backend...");

        const res = await fetch(PUSH_TOKEN_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({ push_token: token }),
        });

        if (!res.ok) {
          const body = await res.text();
          log("[PUSH] Failed to register token:", res.status, body);
          return false;
        }

        log("[PUSH] Token registered with backend successfully");
        return true;
      } catch (e: any) {
        log("[PUSH] Error registering token with backend:", e?.message);
        return false;
      }
    },
    [expoPushToken]
  );

  /**
   * Remove push token from backend (on logout)
   */
  const unregisterTokenFromBackend = useCallback(
    async (accessToken: string): Promise<boolean> => {
      try {
        log("[PUSH] Unregistering token from backend...");

        const res = await fetch(PUSH_TOKEN_URL, {
          method: "DELETE",
          headers: {
            Authorization: `Bearer ${accessToken}`,
          },
        });

        if (!res.ok) {
          log("[PUSH] Failed to unregister token:", res.status);
          return false;
        }

        log("[PUSH] Token unregistered from backend");
        setExpoPushToken(null);
        return true;
      } catch (e: any) {
        log("[PUSH] Error unregistering token:", e?.message);
        return false;
      }
    },
    []
  );

  /**
   * Clear badge count
   */
  const clearBadge = useCallback(async () => {
    await Notifications.setBadgeCountAsync(0);
  }, []);

  /**
   * Set up notification listeners
   * Note: Some functionality is limited in Expo Go - use development build for full testing
   */
  useEffect(() => {
    try {
      // Listener for notifications received while app is foregrounded
      notificationListener.current = Notifications.addNotificationReceivedListener(
        (notification) => {
          log("[PUSH] Notification received:", notification.request.content.title);
          setNotification(notification);
          onNotificationReceived?.(notification);
        }
      );

      // Listener for when user taps on a notification
      responseListener.current = Notifications.addNotificationResponseReceivedListener(
        (response) => {
          log("[PUSH] Notification tapped");
          const data = response.notification.request.content.data as NotificationData;

          // Clear badge when user interacts with notification
          Notifications.setBadgeCountAsync(0);

          onNotificationTapped?.(data);
        }
      );
    } catch (e) {
      log("[PUSH] Listener setup limited in Expo Go:", e);
    }

    return () => {
      // Use .remove() method on subscription (newer API)
      // Wrapped in try-catch for Expo Go compatibility
      try {
        notificationListener.current?.remove();
        responseListener.current?.remove();
      } catch (e) {
        // Safe to ignore - expected in Expo Go
      }
    };
  }, [onNotificationReceived, onNotificationTapped]);

  /**
   * Check if we should prompt for permissions
   * (Don't prompt if already denied - respect user's choice)
   */
  const shouldPromptForPermission = useCallback(async (): Promise<boolean> => {
    if (!Device.isDevice) return false;

    const { status } = await Notifications.getPermissionsAsync();
    // Only prompt if status is undetermined
    return status === "undetermined";
  }, []);

  return {
    // State
    expoPushToken,
    notification,
    error,
    permissionStatus,

    // Actions
    registerForPushNotifications,
    registerTokenWithBackend,
    unregisterTokenFromBackend,
    clearBadge,
    shouldPromptForPermission,
  };
}

/**
 * Get the last notification response (for handling app opened via notification)
 */
export async function getLastNotificationResponse(): Promise<NotificationData | null> {
  const response = await Notifications.getLastNotificationResponseAsync();
  if (response) {
    return response.notification.request.content.data as NotificationData;
  }
  return null;
}

/**
 * Clear the stored notification tap so cold-start handling does not re-navigate
 * on every subsequent WebView load.
 */
export async function clearLastNotificationResponse(): Promise<void> {
  try {
    await Notifications.clearLastNotificationResponseAsync();
  } catch {
    // Unavailable in Expo Go — safe to ignore.
  }
}
