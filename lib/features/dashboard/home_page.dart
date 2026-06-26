import 'package:flutter/material.dart';

import '../guests/guests_page.dart';
import '../more/more_page.dart';
import '../parcels/parcels_page.dart';
import '../reservations/reservations_page.dart';
import 'dashboard_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  bool _openReservationsWithDebt = false;

  static const _titles = ['Početna', 'Rezervacije', 'Parcele', 'Gosti', 'Više'];

  void _openReservations() {
    setState(() {
      _openReservationsWithDebt = false;
      _currentIndex = 1;
    });
  }

  void _openReservationsWithDebtFilter() {
    setState(() {
      _openReservationsWithDebt = true;
      _currentIndex = 1;
    });
  }

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return DashboardPage(
          onNewReservation: _openReservations,
          onOpenDebtReservations: _openReservationsWithDebtFilter,
        );
      case 1:
        return ReservationsPage(initialDebtOnly: _openReservationsWithDebt);
      case 2:
        return const ParcelsPage();
      case 3:
        return GuestsPage();
      case 4:
        return const MorePage();
      default:
        return DashboardPage(
          onNewReservation: _openReservations,
          onOpenDebtReservations: _openReservationsWithDebtFilter,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_currentIndex])),
      body: _buildCurrentPage(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            if (index == 1) {
              _openReservationsWithDebt = false;
            }
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Početna',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Rezervacije',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Parcele',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group_rounded),
            label: 'Gosti',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_outlined),
            selectedIcon: Icon(Icons.more_horiz_rounded),
            label: 'Više',
          ),
        ],
      ),
    );
  }
}
