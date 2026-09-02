import '@expo/metro-runtime';
import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { ActivityIndicator, View, StyleSheet, StatusBar } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import AuthProvider, { useAuth } from './src/contexts/AuthContext';
import { PlayerProvider } from './src/contexts/PlayerContext';
import ServerSelectScreen from './src/screens/ServerSelectScreen';
import LoginScreen from './src/screens/LoginScreen';
import TabNavigator from './src/navigation/TabNavigator';
import { RootStackParamList } from './src/types/navigation';

const Stack = createNativeStackNavigator<RootStackParamList>();

const Navigation = () => {
  const { isAuthenticated, isLoading } = useAuth();

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <SafeAreaView style={styles.safeArea}>
          <ActivityIndicator size="large" color="#2196F3" />
        </SafeAreaView>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <SafeAreaView style={styles.safeArea}>
        <Stack.Navigator
          screenOptions={{
            headerShown: false,
            animation: 'slide_from_right',
          }}
          initialRouteName={isAuthenticated ? 'Home' : 'ServerSelect'}
        >
          {!isAuthenticated ? (
            <>
              <Stack.Screen name="ServerSelect" component={ServerSelectScreen} />
              <Stack.Screen name="Login" component={LoginScreen} />
            </>
          ) : (
            <Stack.Screen name="Home">
              {() => (
                <View style={styles.content}>
                  <TabNavigator />
                </View>
              )}
            </Stack.Screen>
          )}
        </Stack.Navigator>
      </SafeAreaView>
    </View>
  );
};

const App = () => {
  return (
    <SafeAreaProvider>
      <StatusBar
        barStyle="light-content"
        backgroundColor="#0a1428"
        translucent={true}
      />
      <AuthProvider>
        <PlayerProvider>
          <NavigationContainer>
            <Navigation />
          </NavigationContainer>
        </PlayerProvider>
      </AuthProvider>
    </SafeAreaProvider>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0a1428',
  },
  safeArea: {
    flex: 1,
    backgroundColor: '#0a1428',
  },
  content: {
    flex: 1,
  },
  loadingContainer: {
    flex: 1,
    backgroundColor: '#0a1428',
  },
});

export default App;
